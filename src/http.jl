# The request layer.
#
# Two things shape this file. First, network courtesy: OBIS publishes no request quota and
# asks users not to parallelize downloads, so requests are serial, identified, and backed
# off on failure. Second, the API's error reporting: an HTTP 200 can carry a failure in the
# body, and an HTTP 500 can carry a well-formed empty result set, so status alone never
# decides whether a response is usable.

"""
    Transport

Function that performs one HTTP GET and returns `(status, headers, body)`.

Swappable so the test suite can serve recorded fixtures without reaching the network.
"""
const TRANSPORT = Ref{Any}(nothing)

"""
    default_transport(url, headers, timeout) -> (status, headers, body)

Perform one HTTP GET with `HTTP.jl`.

`status_exception = false` because the API uses 4xx and 5xx bodies to explain failures, and
those bodies are more informative than the status code.
"""
function default_transport(url::AbstractString, headers, timeout::Integer)
    r = HTTP.get(
        url;
        headers=headers,
        status_exception=false,
        readtimeout=timeout,
        connect_timeout=timeout,
        retry=false,          # retries and backoff are handled here, with OBIS-aware rules
        redirect=true,
    )
    return (
        r.status,
        Dict(lowercase(String(k)) => String(v) for (k, v) in r.headers),
        String(r.body),
    )
end

"""
    DOWNLOADER

Function that writes the body at `url` to the file at `path`, given request headers.

The second seam beside [`TRANSPORT`](@ref), and separate from it because a bulk export is a
file rather than a response: it goes to disk as it arrives instead of being held in memory,
so it cannot share the transport's `(status, headers, body)` shape. Swappable for the same
reason — the export route has to be testable without reaching AWS.
"""
const DOWNLOADER = Ref{Any}(nothing)

"""
    default_downloader(url, path, headers) -> String

Stream `url` into `path` with `HTTP.jl`.

`update_period = Inf` silences `HTTP.jl`'s own progress logging: the package reports
progress itself, and two indicators disagreeing is worse than neither.
"""
function default_downloader(url::AbstractString, path::AbstractString, headers)
    HTTP.download(url, path; headers=headers, update_period=Inf)
    return path
end

"Timestamp of the last request, used to honour `request_gap`."
const LAST_REQUEST = Ref(0.0)

"""
    build_url(endpoint, params; base_url) -> String

Join an endpoint path and query parameters into a request URL.
"""
function build_url(endpoint::AbstractString, params::QueryParams; base_url::AbstractString)
    path = lstrip(String(endpoint), '/')
    url = string(base_url, path)
    isempty(params) && return url
    query = join(
        (string(HTTP.escapeuri(k), '=', HTTP.escapeuri(v)) for (k, v) in pairs(params)), '&'
    )
    return string(url, '?', query)
end

"""
    MAX_URL_LENGTH

Longest request URL the API accepts, in characters. Beyond about 8,060 it answers HTTP 400
with an empty body (NOTES.md section 3.6), which says nothing about why.
"""
const MAX_URL_LENGTH = 8000

"""
    check_url_length(url, params)

Refuse a URL the API would reject for its length, naming the parameter that made it long.

In practice that is always `geometry`: a coastline or an EEZ read from a shapefile runs to
thousands of vertices, and every one travels in the query string.
"""
function check_url_length(url::AbstractString, params::QueryParams)
    n = length(url)
    n <= MAX_URL_LENGTH && return nothing
    if haskey(params, "geometry")
        wkt = get(params, "geometry", "")
        throw(
            OBISValidationError(
                :geometry,
                string(first(wkt, 60), "…"),
                "The geometry makes the request URL $(n) characters long, and the API " *
                "rejects URLs over about $(MAX_URL_LENGTH) with an empty HTTP 400. " *
                "Simplify the polygon to a few hundred vertices (GeometryOps.simplify, or " *
                "a GIS), query its bounding box with `OBISClient.bbox` and filter the " *
                "records locally, or use an `areaid` if OBIS already knows the region " *
                "(`OBISClient.area()`).",
            ),
        )
    end
    throw(
        OBISValidationError(
            :params,
            nothing,
            "The request URL is $(n) characters long, and the API rejects URLs over about " *
            "$(MAX_URL_LENGTH). Shorten the longest parameters.",
        ),
    )
end

"""
    request_headers(cfg) -> Vector{Pair{String,String}}

Headers sent on every request.

The `User-Agent` names the package, its version and its repository so OBIS can tell which
client is generating traffic and reach the maintainers if it misbehaves.
"""
function request_headers(cfg::ClientConfig)
    return [
        "User-Agent" => cfg.user_agent,
        "Accept" => "application/json",
        "Accept-Encoding" => "gzip",
    ]
end

"""
    retryable(status, body) -> Bool

Whether a failed response is worth retrying.

429 and 5xx are transient in general, but the API also answers permanent client mistakes
with 5xx and an explanatory `error` field in the body, and retrying those only wastes the
server's time.
"""
function retryable(status::Integer, body::AbstractString)
    status == 429 && return true
    status >= 500 || return false
    return !occursin("\"error\"", body)
end

"""
    backoff_delay(attempt, cfg, retry_after) -> Float64

Delay before retry number `attempt`, honouring a `Retry-After` header when the server
sends one and otherwise doubling from `backoff_base` up to `backoff_max`.

A small deterministic jitter spreads retries from concurrent sessions.
"""
function backoff_delay(
    attempt::Integer, cfg::ClientConfig, retry_after::Union{Nothing,Real}
)
    retry_after === nothing || return min(Float64(retry_after), cfg.backoff_max)
    base = cfg.backoff_base * 2.0^(attempt - 1)
    return min(base, cfg.backoff_max) * (0.75 + 0.5 * rand())
end

function parse_retry_after(headers)
    v = get(headers, "retry-after", nothing)
    v === nothing && return nothing
    n = tryparse(Float64, strip(v))
    return n
end

"""
    throttle!(cfg)

Sleep, if needed, so consecutive requests are at least `request_gap` seconds apart.
"""
function throttle!(cfg::ClientConfig)
    cfg.request_gap > 0 || return nothing
    elapsed = time() - LAST_REQUEST[]
    elapsed < cfg.request_gap && sleep(cfg.request_gap - elapsed)
    return nothing
end

"""
    raw_request(endpoint, params; cfg, headers = []) -> (body::String, headers::Dict, status::Int)

Perform one request with retries and backoff, returning the raw response body.

`headers` are sent in addition to the usual ones; [`revalidate_cache`](@ref) uses them for
`If-None-Match`, and reads the status to tell a `304 Not Modified` from a response whose
body happens to be empty.

Raises [`OBISConnectionError`](@ref) when the retry budget is exhausted and
[`OBISAPIError`](@ref) for a permanent failure. Response *content* is not inspected here;
that is [`check_response`](@ref)'s job.
"""
function raw_request(
    endpoint::AbstractString,
    params::QueryParams;
    cfg::ClientConfig=CONFIG,
    headers=Pair{String,String}[],
)
    url = build_url(endpoint, params; base_url=cfg.base_url)
    check_url_length(url, params)
    headers = vcat(request_headers(cfg), headers)
    transport = TRANSPORT[] === nothing ? default_transport : TRANSPORT[]

    last_message = "no response"
    last_status = 0
    last_body = ""

    for attempt in 1:(cfg.retries + 1)
        throttle!(cfg)
        LAST_REQUEST[] = time()

        status, resp_headers, body = try
            transport(url, headers, cfg.timeout)
        catch err
            err isa OBISError && rethrow()
            last_message = sprint(showerror, err)
            last_status = 0
            if attempt <= cfg.retries
                sleep(backoff_delay(attempt, cfg, nothing))
                continue
            end
            throw(
                OBISConnectionError(
                    url,
                    "Request failed after $(cfg.retries + 1) attempts. Last error: " *
                    last_message,
                ),
            )
        end

        if status < 400
            return body, resp_headers, Int(status)
        end

        last_status, last_body = status, body

        if retryable(status, body) && attempt <= cfg.retries
            delay = backoff_delay(attempt, cfg, parse_retry_after(resp_headers))
            @debug "OBIS request failed; backing off" status attempt delay endpoint
            sleep(delay)
            continue
        end

        throw(OBISAPIError(status, endpoint, http_error_advice(status, body), body))
    end

    throw(
        OBISConnectionError(
            url,
            "Gave up after $(cfg.retries + 1) attempts. Last status: $(last_status). " *
            "Last body: $(first(last_body, 200))",
        ),
    )
end

"""
    http_error_advice(status, body) -> String

Turn an HTTP status into a sentence the caller can act on.
"""
function http_error_advice(status::Integer, body::AbstractString)
    if status == 400
        return "The API rejected the request. Its explanation is below; if it mentions a " *
               "size limit, lower `page_size` with `OBISClient.configure!`."
    elseif status == 404
        return "No such endpoint. Check the path against the endpoints listed in the " *
               "package documentation."
    elseif status == 429
        return "Rate limited, and the retry budget is exhausted. Slow down with " *
               "`OBISClient.configure!(request_gap = 1.0)` and try again."
    elseif status >= 500
        return "The OBIS service reported a server error. When the body names a specific " *
               "parameter, the request itself is at fault and retrying will not help."
    end
    return "The request failed."
end

"""
    check_response(payload, endpoint, params) -> payload

Inspect a decoded response body for failures the HTTP status did not report.

The API returns `NAME_NOT_FOUND` inside an HTTP 200 for an unmatched scientific name, and
returns other errors in the same `error` field. Both are raised here so that an empty
result set always means "no records matched", never "the query was wrong".
"""
function check_response(payload, endpoint::AbstractString, params::QueryParams)
    payload isa JSON3.Object || return payload
    haskey(payload, :error) || return payload

    err = payload[:error]
    err === nothing && return payload
    message = String(string(err))

    if message == "NAME_NOT_FOUND"
        throw(OBISNameNotFoundError(get(params, "scientificname", "(unspecified)")))
    end

    throw(
        OBISAPIError(
            200,
            endpoint,
            "The API accepted the request but reported an error, and returned no usable " *
            "records. The response status was not an error status, so this would " *
            "otherwise look like an empty result.",
            message,
        ),
    )
end

"""
    api_get(endpoint, params; cfg, allow_empty = false) -> JSON3 payload

Fetch and decode one API response, consulting the cache when one is configured.

This is the single point every endpoint goes through, so caching, courtesy pacing and
error interpretation apply uniformly.

`allow_empty` returns `nothing` for an empty body instead of raising. Only
`/occurrence/centroid` needs it: it answers a query that matches no records with an empty
HTTP 200, where every other endpoint sends an empty result set.
"""
function api_get(
    endpoint::AbstractString,
    params::QueryParams=QueryParams();
    cfg::ClientConfig=CONFIG,
    allow_empty::Bool=false,
)
    body = cached_body(cfg.cache, endpoint, params)
    if body === nothing
        body, headers, _ = raw_request(endpoint, params; cfg=cfg)
        store_body!(cfg.cache, endpoint, params, body, headers)
    end
    allow_empty && isempty(strip(body)) && return nothing

    payload = try
        JSON3.read(body)
    catch err
        throw(
            OBISAPIError(
                0,
                endpoint,
                "The response was not valid JSON. This usually means the request reached " *
                "something other than the API — a proxy or an error page. Error: " *
                sprint(showerror, err),
                first(body, 300),
            ),
        )
    end

    return check_response(payload, endpoint, params)
end

"""
    results_of(payload) -> Vector

Extract the `results` array from a standard `{total, results}` envelope.

Several endpoints answer with a bare object or a bare array instead, so this returns an
empty vector rather than raising when the key is absent, and callers that expect another
shape read the payload directly.
"""
function results_of(payload)
    payload isa JSON3.Array && return collect(payload)
    payload isa JSON3.Object || return Any[]
    haskey(payload, :results) || return Any[]
    r = payload[:results]
    r === nothing && return Any[]
    return r isa JSON3.Array ? collect(r) : Any[r]
end

"""
    total_of(payload, fallback) -> Int

Read the `total` field of a response envelope, falling back when it is absent.
"""
function total_of(payload, fallback::Integer=0)
    payload isa JSON3.Object || return Int(fallback)
    haskey(payload, :total) || return Int(fallback)
    t = payload[:total]
    return t === nothing ? Int(fallback) : Int(t)
end

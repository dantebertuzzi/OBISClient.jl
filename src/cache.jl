# Local response cache, addressed by a hash of the query.
#
# The purpose is reproducibility rather than speed. OBIS ingests new records continuously,
# so the same query run twice returns different data, and an analysis published today
# cannot be re-run against the data it was based on unless something kept a copy. Storing
# the raw response body alongside the query and the retrieval date makes that possible, and
# keeps the stored artifact independent of this package's parsing decisions.

"""
    QueryCache(dir = default_cache_dir(); readonly = false)

A local, content-addressed cache of raw API responses.

Each entry is keyed by a hash of the base URL, endpoint and query parameters, and stores
the unparsed response body next to a metadata record giving the endpoint, the parameters,
the retrieval timestamp and the response `ETag`. Storing the raw body means a re-run
reproduces the original data even if this package's schema handling has changed since.

Entries never expire. That is the point: an expiring cache cannot support "re-run this
analysis against the data as it stood in March". Remove entries explicitly with
[`clear_cache!`](@ref).

# Examples

```julia
# Cache into the default location for the rest of the session.
OBISClient.configure!(cache = OBISClient.QueryCache())

# Keep an analysis's data alongside the analysis.
OBISClient.configure!(cache = OBISClient.QueryCache("data/obis-cache"))

# Re-run later against exactly what was fetched, refusing to reach the network.
OBISClient.configure!(cache = OBISClient.QueryCache("data/obis-cache"; readonly = true))
```
"""
struct QueryCache
    dir::String
    readonly::Bool
end

function QueryCache(dir::AbstractString=default_cache_dir(); readonly::Bool=false)
    return QueryCache(String(dir), readonly)
end

"""
    default_cache_dir() -> String

Default cache location, honouring `XDG_CACHE_HOME` where it is set.
"""
function default_cache_dir()
    xdg = get(ENV, "XDG_CACHE_HOME", "")
    base = isempty(xdg) ? joinpath(homedir(), ".cache") : xdg
    return joinpath(base, "OBISClient.jl")
end

"""
    cache_key(endpoint, params; base_url) -> String

Hash a query into a stable cache key.

Parameters are sorted before hashing so that keyword order does not change the key, which
is what lets the same query written two different ways hit the same entry.
"""
function cache_key(endpoint::AbstractString, params::QueryParams; base_url::AbstractString)
    io = IOBuffer()
    print(io, base_url, '\n', lstrip(String(endpoint), '/'), '\n')
    for (k, v) in sorted_pairs(params)
        print(io, k, '=', v, '\n')
    end
    return bytes2hex(SHA.sha256(take!(io)))
end

entry_path(cache::QueryCache, key::AbstractString) = joinpath(cache.dir, key * ".json")
meta_path(cache::QueryCache, key::AbstractString) = joinpath(cache.dir, key * ".meta.json")

"""
    cached_body(cache, endpoint, params) -> Union{Nothing,String}

Return a stored response body, or `nothing` when the query is not cached.
"""
cached_body(::Nothing, ::AbstractString, ::QueryParams) = nothing

function cached_body(cache::QueryCache, endpoint::AbstractString, params::QueryParams)
    key = cache_key(endpoint, params; base_url=CONFIG.base_url)
    path = entry_path(cache, key)
    isfile(path) || begin
        if cache.readonly
            throw(
                OBISAPIError(
                    0,
                    endpoint,
                    "The cache is read-only and holds no entry for this query, so the " *
                    "package will not reach the network for it. Either this query differs " *
                    "from the one that was cached, or the cache directory " *
                    "($(cache.dir)) is not the one that was written. Set " *
                    "`readonly = false` to fetch it.",
                    "",
                ),
            )
        end
        return nothing
    end
    return read(path, String)
end

"""
    store_body!(cache, endpoint, params, body, headers)

Write a response body and its provenance metadata into the cache.
"""
store_body!(::Nothing, ::AbstractString, ::QueryParams, ::AbstractString, ::Any) = nothing

function store_body!(
    cache::QueryCache,
    endpoint::AbstractString,
    params::QueryParams,
    body::AbstractString,
    headers,
)
    cache.readonly && return nothing
    mkpath(cache.dir)
    key = cache_key(endpoint, params; base_url=CONFIG.base_url)

    meta = Dict{String,Any}(
        "endpoint" => lstrip(String(endpoint), '/'),
        "base_url" => CONFIG.base_url,
        "parameters" => Dict(k => v for (k, v) in sorted_pairs(params)),
        "retrieved" => string(now(UTC)),
        "accessed" => string(today()),
        "package_version" => string(package_version()),
        "etag" => headers isa AbstractDict ? get(headers, "etag", "") : "",
    )

    # Write through a temporary file so an interrupted run cannot leave a truncated entry
    # that would later be served as if it were complete.
    tmp = entry_path(cache, key) * ".tmp"
    write(tmp, body)
    mv(tmp, entry_path(cache, key); force=true)

    tmpm = meta_path(cache, key) * ".tmp"
    open(tmpm, "w") do io
        JSON3.write(io, meta)
    end
    mv(tmpm, meta_path(cache, key); force=true)
    return nothing
end

"""
    cache_entries(cache = config().cache) -> Vector{Dict{String,Any}}

List what a cache holds: endpoint, parameters, retrieval time and size for each entry.

```julia
for e in OBISClient.cache_entries()
    println(e["endpoint"], "  ", e["retrieved"])
end
```
"""
function cache_entries(cache=CONFIG.cache)
    cache === nothing && return Dict{String,Any}[]
    isdir(cache.dir) || return Dict{String,Any}[]
    out = Dict{String,Any}[]
    for f in sort(readdir(cache.dir))
        endswith(f, ".meta.json") || continue
        meta = try
            copy(JSON3.read(read(joinpath(cache.dir, f), String), Dict{String,Any}))
        catch
            continue
        end
        key = replace(f, ".meta.json" => "")
        body = entry_path(cache, key)
        meta["key"] = key
        meta["bytes"] = isfile(body) ? filesize(body) : 0
        push!(out, meta)
    end
    return out
end

"""
    clear_cache!(cache = config().cache) -> Int

Delete every entry in a cache and return how many were removed.
"""
function clear_cache!(cache=CONFIG.cache)
    cache === nothing && return 0
    isdir(cache.dir) || return 0
    n = 0
    for f in readdir(cache.dir)
        endswith(f, ".json") || continue
        rm(joinpath(cache.dir, f); force=true)
        endswith(f, ".meta.json") && (n += 1)
    end
    return n
end

"""
    revalidate_cache(cache = config().cache; update = false) -> Vector{NamedTuple}

Ask OBIS, entry by entry, whether the data a cache holds has changed since it was fetched.

Each entry is re-requested with its stored `ETag` in `If-None-Match`. An unchanged response
costs a `304 Not Modified` and no body, so checking a large cache is cheap. Where the server
does send a body, it is compared with the stored one byte for byte, so an entry is reported
`:changed` only when its data really differs.

The cache itself is left alone unless `update = true`, which overwrites each changed entry
with the current response and its new retrieval date. That gives up the old data, which is
the cache's whole purpose, so it is never the default: a re-run that should reproduce a
published result wants to know that the data moved, not to follow it.

Returns one row per entry, with `key`, `endpoint`, `parameters`, `retrieved` (when the stored
copy was fetched) and `status`, one of:

  - `:unchanged` — OBIS would return the same body today;
  - `:changed` — it would not (and, with `update = true`, the entry now holds the new one);
  - `:skipped` — the entry was fetched from a different `base_url` than the one configured;
  - `:failed` — the request failed, with the reason logged as a warning.

The result is a Tables.jl row table, so `DataFrame(revalidate_cache())` works.

```julia
julia> OBISClient.configure!(cache = OBISClient.QueryCache("data/obis-cache"));

julia> report = OBISClient.revalidate_cache();

julia> [r.endpoint for r in report if r.status === :changed]
1-element Vector{String}:
 "occurrence"
```
"""
function revalidate_cache(cache=CONFIG.cache; update::Bool=false)
    cache === nothing && throw(
        OBISValidationError(
            :cache,
            nothing,
            "No cache is configured. Pass one, or set it with " *
            "`OBISClient.configure!(cache = OBISClient.QueryCache(dir))`.",
        ),
    )
    update && cache.readonly &&
        throw(
            OBISValidationError(
                :update,
                true,
                "The cache is read-only, so its entries cannot be replaced. Open it with " *
                "`readonly = false` to update it, or revalidate without `update` to only report.",
            ),
        )

    Row = @NamedTuple{
        key::String,
        endpoint::String,
        parameters::Dict{String,String},
        retrieved::String,
        status::Symbol,
    }
    out = Row[]
    for e in cache_entries(cache)
        key = String(e["key"])
        endpoint = String(e["endpoint"])
        parameters = Dict{String,String}(
            String(k) => String(string(v)) for (k, v) in get(e, "parameters", Dict())
        )
        retrieved = String(string(get(e, "retrieved", "")))
        row(status) = Row((key, endpoint, parameters, retrieved, status))

        if String(string(get(e, "base_url", CONFIG.base_url))) != CONFIG.base_url
            push!(out, row(:skipped))
            continue
        end

        params = QueryParams()
        for (k, v) in sort!(collect(parameters); by=first)
            params[k] = v
        end
        etag = String(string(get(e, "etag", "")))
        extra = isempty(etag) ? Pair{String,String}[] : ["If-None-Match" => etag]

        body, headers, status = try
            raw_request(endpoint, params; headers=extra)
        catch err
            err isa OBISError || rethrow()
            @warn "Could not revalidate a cache entry" endpoint parameters err
            push!(out, row(:failed))
            continue
        end
        if status == 304 || body == read(entry_path(cache, key), String)
            push!(out, row(:unchanged))
            continue
        end
        update && store_body!(cache, endpoint, params, body, headers)
        push!(out, row(:changed))
    end
    return out
end

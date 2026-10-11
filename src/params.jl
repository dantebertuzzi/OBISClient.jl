# Query parameter validation and serialization.
#
# The API ignores unknown parameters and answers many invalid values with an empty result
# set and HTTP 200 (NOTES.md section 8). An empty result is indistinguishable from a
# genuine absence of records, so a mistake here is silent and produces a wrong scientific
# conclusion rather than an error. Everything that can be checked is therefore checked
# before the request goes out.

"""
    RECORD_SELECTIONS

The three values `absence`, `dropped` and `event` accept.

  - `:exclude` — leave them out. The API default.
  - `:include` — return them alongside ordinary records.
  - `:only` — return only these records.

Used by the `absence`, `dropped` and `event` keywords. The distinction matters: `:include`
and `:only` answer different questions, and a boolean keyword could not express both.
"""
const RECORD_SELECTIONS = (:exclude, :include, :only)

"""
    selection_value(name, sel) -> Union{Nothing,String}

Translate one of [`RECORD_SELECTIONS`](@ref) into the string the API expects, or `nothing` when
the parameter should be omitted entirely.
"""
function selection_value(name::Symbol, sel)
    sel === nothing && return nothing
    s = Symbol(sel)
    s === :exclude && return nothing
    s === :include && return "include"
    s === :only && return "true"
    # `true`/`false` are a natural guess, so translate them rather than rejecting outright.
    sel === true && return "true"
    sel === false && return nothing
    throw(
        OBISValidationError(
            name,
            sel,
            "Use `:exclude` to leave these records out (the default), `:include` to add " *
            "them to ordinary records, or `:only` to retrieve just them. These are three " *
            "different queries, which is why this is not a boolean.",
        ),
    )
end

"""
    validate_geometry(wkt) -> String

Check that `wkt` looks like well-formed WKT before sending it.

The API answers invalid WKT with HTTP 200 and an empty result set and no error field, so
an unchecked typo silently reads as "no records in this area". This performs a structural
check — a recognized geometry keyword and balanced parentheses — not a full parse.
"""
function validate_geometry(wkt::AbstractString)
    s = strip(String(wkt))
    isempty(s) && throw(
        OBISValidationError(:geometry, wkt, "The geometry must not be empty.")
    )

    kinds = (
        "POINT",
        "LINESTRING",
        "POLYGON",
        "MULTIPOINT",
        "MULTILINESTRING",
        "MULTIPOLYGON",
        "GEOMETRYCOLLECTION",
    )
    upper = uppercase(s)
    if !any(startswith(upper, k) for k in kinds)
        throw(
            OBISValidationError(
                :geometry,
                s,
                "Expected WKT starting with one of $(join(kinds, ", ")). The API returns " *
                "an empty result set for unparseable geometry without reporting an error, " *
                "so this is checked here. Build a polygon at https://wktmap.com if needed. " *
                "Example: \"POLYGON ((2.3 51.8, 2.3 51.6, 2.6 51.6, 2.6 51.8, 2.3 51.8))\".",
            ),
        )
    end

    depth = 0
    for c in s
        c == '(' && (depth += 1)
        c == ')' && (depth -= 1)
        depth < 0 && throw(
            OBISValidationError(
                :geometry, s, "Unbalanced parentheses: a ')' appears before its '('."
            ),
        )
    end
    depth == 0 || throw(
        OBISValidationError(
            :geometry, s, "Unbalanced parentheses: $(depth) '(' left unclosed."
        ),
    )

    return String(s)
end

"""
    geometry_wkt(geometry) -> String

The WKT to send for a `geometry` filter.

A string is taken as WKT. Anything else is converted by [`geointerface_wkt`](@ref), which
the GeoInterface extension provides, so a polygon read from a shapefile or GeoJSON can be
passed as it is.
"""
geometry_wkt(wkt::AbstractString) = String(wkt)

function geometry_wkt(geometry)
    isempty(methods(geointerface_wkt)) && throw(
        OBISValidationError(
            :geometry,
            typeof(geometry),
            "Pass the geometry as WKT, for example `OBISClient.bbox(west, south, east, " *
            "north)`. To pass a polygon from Shapefile.jl, GeoJSON.jl, ArchGDAL or any " *
            "other GeoInterface-compatible package, load GeoInterface first " *
            "(`using GeoInterface`), which enables the conversion.",
        ),
    )
    return geointerface_wkt(geometry)
end

"""
    geointerface_wkt(geometry) -> String

Write a GeoInterface geometry, or the geometry of a GeoInterface feature, as WKT.

Has no methods until GeoInterface is loaded; the `OBISClientGeoInterfaceExt` extension
supplies them.
"""
function geointerface_wkt end

"""
    format_date(name, value) -> String

Render a date as the `YYYY-MM-DD` string the API requires.

Accepts `Date`, `DateTime`, or a string already in that form. A malformed date is one of
the few inputs the API does report, but with HTTP 500 and a body that still looks like a
valid empty result, so it is checked here instead.
"""
format_date(::Symbol, d::Date) = Dates.format(d, dateformat"yyyy-mm-dd")
format_date(name::Symbol, d::DateTime) = format_date(name, Date(d))

function format_date(name::Symbol, s::AbstractString)
    str = strip(String(s))
    m = match(r"^\d{4}-\d{2}-\d{2}$", str)
    m === nothing && throw(
        OBISValidationError(
            name,
            s,
            "Dates must be formatted as YYYY-MM-DD. Pass a `Date` to have this handled " *
            "for you, for example `$(name) = Date(2015, 5, 29)`.",
        ),
    )
    try
        Date(str, dateformat"yyyy-mm-dd")
    catch
        throw(OBISValidationError(name, s, "Not a valid calendar date."))
    end
    return String(str)
end

function format_date(name::Symbol, x)
    throw(
        OBISValidationError(
            name, x, "Expected a `Date`, a `DateTime`, or a \"YYYY-MM-DD\" string."
        ),
    )
end

"""
    validate_depth(name, value) -> Int

Check a depth bound. Depths are metres below the surface and increase downwards.
"""
function validate_depth(name::Symbol, value)
    v = try
        convert(Int, value)
    catch
        throw(
            OBISValidationError(
                name, value, "Depth must be a whole number of metres below the surface."
            ),
        )
    end
    if !(-100_000 <= v <= 11_000)
        throw(
            OBISValidationError(
                name,
                v,
                "Depth is outside the range the OBIS quality pipeline accepts " *
                "(-100000 to 11000 metres). Values beyond it match no records.",
            ),
        )
    end
    return v
end

"""
    validate_uuid(name, value) -> String

Check that an identifier looks like the UUID the API expects.

Dataset and node identifiers are UUIDs. A malformed one matches nothing and the API
reports no error, so the shape is checked before sending.
"""
function validate_uuid(name::Symbol, value)
    s = strip(String(string(value)))
    if match(
        r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", s
    ) ===
        nothing
        throw(
            OBISValidationError(
                name,
                value,
                "Expected a UUID such as \"8acba7e7-2e50-4490-8328-b78a30472508\". " *
                "A dataset UUID appears in the URL of its page on obis.org; a node UUID " *
                "is listed by `OBISClient.node()`.",
            ),
        )
    end
    return String(s)
end

"""
    validate_size(value) -> Int

Check a page size against the API maximum.
"""
function validate_size(value)
    v = try
        convert(Int, value)
    catch
        throw(OBISValidationError(:size, value, "Page size must be a whole number."))
    end
    if !(1 <= v <= MAX_PAGE_SIZE)
        throw(
            OBISValidationError(
                :size,
                v,
                "Page size must be between 1 and $(MAX_PAGE_SIZE); the API rejects " *
                "anything larger with HTTP 400.",
            ),
        )
    end
    return v
end

"""
    validate_fields(fields) -> String

Check a `fields` allow-list and render it for the wire.

Two behaviours make this worth checking locally: the API silently discards unknown field
names, so a typo yields a missing column rather than an error; and `flags` cannot be
selected through `fields` at all, even though it is present in every unrestricted record.
"""
function validate_fields(fields)
    names = fields isa AbstractString ? split(fields, ',') : collect(fields)
    out = String[]
    for f in names
        s = strip(String(string(f)))
        isempty(s) && continue
        if s == "flags"
            throw(
                OBISValidationError(
                    :fields,
                    fields,
                    "`flags` cannot be requested through `fields`: the API accepts the " *
                    "request but returns records without it. Omit `fields` to receive " *
                    "flags, or drop `flags` from the list if you do not need them.",
                ),
            )
        end
        push!(out, s)
    end
    isempty(out) && throw(
        OBISValidationError(:fields, fields, "The field list must not be empty.")
    )
    # `id` is the pagination cursor; without it a paginated pull cannot advance.
    "id" in out || pushfirst!(out, "id")
    return join(out, ',')
end

"""
    QueryParams

An ordered, validated set of query parameters.

Order is kept stable so that the cache key derived from a query is reproducible across
sessions and Julia versions.
"""
struct QueryParams
    pairs::Vector{Pair{String,String}}
end

QueryParams() = QueryParams(Pair{String,String}[])

Base.isempty(q::QueryParams) = isempty(q.pairs)
Base.length(q::QueryParams) = length(q.pairs)
Base.pairs(q::QueryParams) = q.pairs

function Base.setindex!(q::QueryParams, value, key::AbstractString)
    value === nothing && return q
    push!(q.pairs, String(key) => String(string(value)))
    return q
end

Base.haskey(q::QueryParams, key::AbstractString) = any(p -> first(p) == key, q.pairs)

function Base.get(q::QueryParams, key::AbstractString, default)
    i = findfirst(p -> first(p) == key, q.pairs)
    return i === nothing ? default : last(q.pairs[i])
end

"""
    sorted_pairs(q::QueryParams) -> Vector{Pair{String,String}}

Parameters in a canonical order, for hashing a query into a cache key.
"""
sorted_pairs(q::QueryParams) = sort(q.pairs; by=first)

"""
    build_params(; kwargs...) -> QueryParams

Validate the filter keywords shared by the OBIS endpoints and render them for the wire.

Keywords map onto API parameters, with three deliberate differences:

  - `aphiaid` is accepted as an alias for `taxonid`, because the identifier is called an
    AphiaID everywhere except in the query string.
  - `absence`, `dropped` and `event` take `:exclude`, `:include` or `:only` rather than a
    boolean, matching the three behaviours the API actually offers.
  - `flags` and `exclude` accept any case and any iterable, and are normalized to the
    upper-case forms the API matches on.
"""
function build_params(;
    scientificname=nothing,
    taxonid=nothing,
    aphiaid=nothing,
    datasetid=nothing,
    areaid=nothing,
    instituteid=nothing,
    nodeid=nothing,
    startdate=nothing,
    enddate=nothing,
    startdepth=nothing,
    enddepth=nothing,
    geometry=nothing,
    redlist=nothing,
    hab=nothing,
    wrims=nothing,
    flags=nothing,
    exclude=nothing,
    tags=nothing,
    absence=nothing,
    dropped=nothing,
    event=nothing,
    mof=nothing,
    dna=nothing,
    extensions=nothing,
    hasextensions=nothing,
    qcfields=nothing,
    measurementtype=nothing,
    measurementtypeid=nothing,
    measurementvalue=nothing,
    measurementvalueid=nothing,
    measurementunit=nothing,
    measurementunitid=nothing,
    facets=nothing,
    composite=nothing,
    size=nothing,
    after=nothing,
    fields=nothing,
)
    q = QueryParams()

    if taxonid !== nothing && aphiaid !== nothing
        throw(
            OBISValidationError(
                :aphiaid,
                aphiaid,
                "`aphiaid` and `taxonid` name the same API parameter; pass only one.",
            ),
        )
    end
    taxon = taxonid === nothing ? aphiaid : taxonid

    if scientificname !== nothing
        s = strip(String(string(scientificname)))
        isempty(s) && throw(
            OBISValidationError(
                :scientificname,
                scientificname,
                "Omit the keyword to search all taxa rather than passing an empty name.",
            ),
        )
        q["scientificname"] = s
    end

    taxon === nothing || (q["taxonid"] = string(taxon))
    datasetid === nothing || (q["datasetid"] = validate_uuid(:datasetid, datasetid))
    nodeid === nothing || (q["nodeid"] = validate_uuid(:nodeid, nodeid))
    areaid === nothing || (q["areaid"] = string(areaid))
    instituteid === nothing || (q["instituteid"] = string(instituteid))

    startdate === nothing || (q["startdate"] = format_date(:startdate, startdate))
    enddate === nothing || (q["enddate"] = format_date(:enddate, enddate))

    if startdate !== nothing && enddate !== nothing
        a = Date(format_date(:startdate, startdate), dateformat"yyyy-mm-dd")
        b = Date(format_date(:enddate, enddate), dateformat"yyyy-mm-dd")
        a <= b || throw(
            OBISValidationError(
                :startdate, startdate,
                "`startdate` ($a) must not be after `enddate` ($b).",
            ),
        )
    end

    sd = startdepth === nothing ? nothing : validate_depth(:startdepth, startdepth)
    ed = enddepth === nothing ? nothing : validate_depth(:enddepth, enddepth)
    if sd !== nothing && ed !== nothing && sd > ed
        throw(
            OBISValidationError(
                :startdepth,
                startdepth,
                "`startdepth` ($sd m) must not be deeper than `enddepth` ($ed m). " *
                "Depth increases downwards from the surface.",
            ),
        )
    end
    sd === nothing || (q["startdepth"] = sd)
    ed === nothing || (q["enddepth"] = ed)

    geometry === nothing || (q["geometry"] = validate_geometry(geometry_wkt(geometry)))

    redlist === nothing || (q["redlist"] = redlist ? "true" : "false")
    hab === nothing || (q["hab"] = hab ? "true" : "false")
    wrims === nothing || (q["wrims"] = wrims ? "true" : "false")
    mof === nothing || (q["mof"] = mof ? "true" : "false")
    dna === nothing || (q["dna"] = dna ? "true" : "false")
    qcfields === nothing || (q["qcfields"] = qcfields ? "true" : "false")
    composite === nothing || (q["composite"] = composite ? "true" : "false")

    flags === nothing || (q["flags"] = join(normalize_flags(flags), ','))
    exclude === nothing || (q["exclude"] = join(normalize_flags(exclude), ','))

    if tags !== nothing
        q["tags"] = tags isa AbstractString ? String(tags) : join(string.(tags), ',')
    end

    q["absence"] = selection_value(:absence, absence)
    q["dropped"] = selection_value(:dropped, dropped)
    q["event"] = selection_value(:event, event)

    extensions === nothing || (q["extensions"] = join_csv(extensions))
    hasextensions === nothing || (q["hasextensions"] = join_csv(hasextensions))

    measurementtype === nothing || (q["measurementtype"] = string(measurementtype))
    measurementtypeid === nothing || (q["measurementtypeid"] = string(measurementtypeid))
    measurementvalue === nothing || (q["measurementvalue"] = string(measurementvalue))
    measurementvalueid === nothing || (q["measurementvalueid"] = string(measurementvalueid))
    measurementunit === nothing || (q["measurementunit"] = string(measurementunit))
    measurementunitid === nothing || (q["measurementunitid"] = string(measurementunitid))

    if facets !== nothing
        q["facets"] = join_csv(facets)
    end

    size === nothing || (q["size"] = validate_size(size))
    after === nothing || (q["after"] = string(after))
    fields === nothing || (q["fields"] = validate_fields(fields))

    return q
end

join_csv(x::AbstractString) = String(x)
join_csv(x) = join(string.(x), ',')

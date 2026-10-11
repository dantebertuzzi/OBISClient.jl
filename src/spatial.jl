# The spatial routes: gridded counts, distinct locations, the centroid, and a helper for
# the bounding boxes most queries are drawn with.
#
# These endpoints aggregate on the server, so a map of a million records costs one request
# instead of a hundred pages. They take the occurrence filters, with one exception verified
# against the live service (NOTES.md section 2.3): they ignore `dropped`. A grid requested
# with `dropped = :include` silently counts the same records as one without, and with
# `dropped = :only` comes back empty, so the keyword is refused here rather than passed on.

"""
    GRID_FEATURE_CAP

Most features `/occurrence/grid` and `/occurrence/points` return. A response this size has
been cut short by the server, which says nothing about it.
"""
const GRID_FEATURE_CAP = 100_000

"""
    GRID_PRECISIONS

Geohash precisions `/occurrence/grid` serves. Precision 0 is a server error, and anything
above 8 returns an empty grid with HTTP 200, which would read as "no records".
"""
const GRID_PRECISIONS = 1:8

"""
    bbox(west, south, east, north) -> String

WKT for a longitude/latitude box, for the `geometry` filter.

Coordinates are in decimal degrees. The ring is closed for you, which is the step most
often forgotten when WKT is written by hand. A box with `west > east` crosses the
antimeridian and is returned as a `MULTIPOLYGON` of its two halves, since a single polygon
cannot express it.

```julia
julia> OBISClient.bbox(2.3, 51.6, 2.6, 51.8)
"POLYGON ((2.3 51.6, 2.6 51.6, 2.6 51.8, 2.3 51.8, 2.3 51.6))"

julia> OBISClient.occurrence("Abra alba"; geometry = OBISClient.bbox(2.0, 51.0, 4.5, 52.5));
```
"""
function bbox(west::Real, south::Real, east::Real, north::Real)
    for (name, v) in ((:west, west), (:east, east))
        -180 <= v <= 180 || throw(
            OBISValidationError(name, v, "Longitude must lie in [-180, 180].")
        )
    end
    for (name, v) in ((:south, south), (:north, north))
        -90 <= v <= 90 || throw(
            OBISValidationError(name, v, "Latitude must lie in [-90, 90].")
        )
    end
    south < north || throw(
        OBISValidationError(
            :south, south, "`south` ($south) must be below `north` ($north)."
        ),
    )
    west == east && throw(
        OBISValidationError(
            :west, west, "`west` and `east` are equal; the box has no width."
        ),
    )

    west < east && return string("POLYGON (", wkt_ring(west, south, east, north), ")")
    return string(
        "MULTIPOLYGON ((",
        wkt_ring(west, south, 180, north),
        "), (",
        wkt_ring(-180, south, east, north),
        "))",
    )
end

function wkt_ring(w, s, e, n)
    corners = ((w, s), (e, s), (e, n), (w, n), (w, s))
    return string("(", join((string(x, ' ', y) for (x, y) in corners), ", "), ")")
end

"""
    spatial_params(endpoint, scientificname; kwargs...) -> QueryParams

The occurrence filters, minus what the aggregating endpoints cannot honour.
"""
function spatial_params(endpoint::AbstractString, scientificname; kwargs...)
    params = build_params(; scientificname=scientificname, kwargs...)
    if haskey(params, "dropped")
        throw(
            OBISValidationError(
                :dropped,
                kwargs[:dropped],
                "`$(endpoint)` ignores the `dropped` filter: with `:include` it counts " *
                "the same records as without, and with `:only` it returns nothing. Query " *
                "dropped records with `OBISClient.occurrence(...; dropped = :only)` and " *
                "aggregate them yourself.",
            ),
        )
    end
    for key in ("size", "after", "fields", "facets")
        haskey(params, key) && throw(
            OBISValidationError(
                Symbol(key),
                get(params, key, nothing),
                "`$(endpoint)` aggregates on the server and takes no `$(key)`.",
            ),
        )
    end
    return params
end

function warn_if_capped(n::Integer, endpoint::AbstractString)
    n >= GRID_FEATURE_CAP || return nothing
    @warn "`$(endpoint)` returned $(n) features, which is the server's cap; the result " *
        "is incomplete. Use a coarser `precision` or narrow the query."
    return nothing
end

"""
    occurrence_grid(scientificname = nothing; precision, kwargs...) -> OBISTable

Record counts per geohash cell, aggregated by OBIS.

One request maps a query of any size, which is the cheap way to draw a distribution or an
effort surface without retrieving the records. Takes the filters of
[`occurrence`](@ref) except `dropped`, which the endpoint ignores.

`precision` is the geohash length, from 1 (cells of 45° × 45°) to 8 (about 0.0003°). Each
step up makes cells 32 times smaller in area. Precision 3 cells are 1.4° square, a
reasonable start for a regional map.

The table has one row per cell with at least one record, with columns:

  - `west`, `south`, `east`, `north`: the cell's bounds, in decimal degrees;
  - `longitude`, `latitude`: its centre;
  - `records`: how many records fall in it.

The server returns at most $(GRID_FEATURE_CAP) cells and does not say when it truncates;
a warning is logged when a result reaches that size.

```julia
julia> g = OBISClient.occurrence_grid("Abra alba"; precision = 3);

julia> sum(g.records) == OBISClient.statistics("Abra alba")["records"]
true
```
"""
function occurrence_grid(scientificname=nothing; precision::Integer, kwargs...)
    precision in GRID_PRECISIONS || throw(
        OBISValidationError(
            :precision,
            precision,
            "Use a geohash precision from $(first(GRID_PRECISIONS)) to " *
            "$(last(GRID_PRECISIONS)). The API fails at 0 and returns an empty grid above " *
            "$(last(GRID_PRECISIONS)), which would look like an absence of records.",
        ),
    )
    endpoint = "occurrence/grid/$(precision)"
    params = spatial_params(endpoint, scientificname; kwargs...)
    payload = api_get(endpoint, params)

    features = payload isa JSON3.Object ? get(payload, :features, nothing) : nothing
    features === nothing && (features = ())
    n = length(features)

    west = Vector{Float64}(undef, n)
    south = Vector{Float64}(undef, n)
    east = Vector{Float64}(undef, n)
    north = Vector{Float64}(undef, n)
    records = Vector{Int}(undef, n)
    for (i, f) in enumerate(features)
        ring = f[:geometry][:coordinates][1]
        west[i] = minimum(Float64(p[1]) for p in ring)
        east[i] = maximum(Float64(p[1]) for p in ring)
        south[i] = minimum(Float64(p[2]) for p in ring)
        north[i] = maximum(Float64(p[2]) for p in ring)
        records[i] = Int(f[:properties][:n])
    end
    warn_if_capped(n, endpoint)

    names = [:west, :south, :east, :north, :longitude, :latitude, :records]
    columns = AbstractVector[
        west, south, east, north, (west .+ east) ./ 2, (south .+ north) ./ 2, records
    ]
    # `total` counts rows, as on every other table; the records are in the `records` column.
    meta = QueryMeta(endpoint, params, n)
    return OBISTable(names, columns, meta)
end

"""
    occurrence_points(scientificname = nothing; kwargs...) -> OBISTable

The distinct locations a query's records occupy, from one request.

OBIS snaps each record to a geohash of precision 8 (about 40 m by 20 m) and returns one
point per occupied cell, without counts. That makes this a map of *where* a taxon has been
recorded, not of how often; use [`occurrence_grid`](@ref) for counts. Takes the filters of
[`occurrence`](@ref) except `dropped`.

The table has columns `longitude` and `latitude`. At most $(GRID_FEATURE_CAP) points
are returned, with a warning when a result reaches that size.

```julia
julia> pts = OBISClient.occurrence_points("Abra alba");

julia> OBISClient.nrow(pts) < OBISClient.statistics("Abra alba")["records"]
true
```
"""
function occurrence_points(scientificname=nothing; kwargs...)
    endpoint = "occurrence/points"
    params = spatial_params(endpoint, scientificname; kwargs...)
    payload = api_get(endpoint, params)

    coords = payload isa JSON3.Object ? get(payload, :coordinates, nothing) : nothing
    coords === nothing && (coords = ())
    lon = Float64[Float64(c[1]) for c in coords]
    lat = Float64[Float64(c[2]) for c in coords]
    warn_if_capped(length(lon), endpoint)

    meta = QueryMeta(endpoint, params, length(lon))
    return OBISTable([:longitude, :latitude], AbstractVector[lon, lat], meta)
end

"""
    occurrence_centroid(scientificname = nothing; kwargs...)
        -> Union{Nothing,NamedTuple{(:longitude,:latitude)}}

The mean position of the records a query matches, computed by OBIS.

Returns `nothing` when no record matches; the endpoint answers that case with an empty
body. Takes the filters of [`occurrence`](@ref) except `dropped`.

The mean is taken over longitude and latitude as plain numbers, so for a taxon recorded on
both sides of the antimeridian it can land far from any record.

```julia
julia> OBISClient.occurrence_centroid("Abra alba")
(longitude = 4.97…, latitude = 54.23…)
```
"""
function occurrence_centroid(scientificname=nothing; kwargs...)
    endpoint = "occurrence/centroid"
    params = spatial_params(endpoint, scientificname; kwargs...)
    payload = api_get(endpoint, params; allow_empty=true)
    payload isa JSON3.Object || return nothing
    lat = get(payload, :lat, nothing)
    lon = get(payload, :lon, nothing)
    (lat === nothing || lon === nothing) && return nothing
    return (longitude=Float64(lon), latitude=Float64(lat))
end

# Getting started

## Querying occurrences

[`OBISClient.occurrence`](@ref) is the main entry point. The first argument is a scientific name
at any rank; everything else is a keyword.

```julia
using OBISClient, Dates

# By name.
OBISClient.occurrence("Abra alba"; limit = 100)

# By AphiaID, which is unambiguous where a name is not.
OBISClient.occurrence(; taxonid = 141433, limit = 100)

# In an area, over a period, within a depth range.
OBISClient.occurrence(;
    scientificname = "Delphinidae",
    geometry  = "POLYGON ((2.0 52.5, 2.0 51.0, 4.5 51.0, 4.5 52.5, 2.0 52.5))",
    startdate = Date(2010, 1, 1),
    enddate   = Date(2020, 12, 31),
    startdepth = 0,
    enddepth   = 200,
)

# From one dataset, one node, or one institute.
OBISClient.occurrence(; datasetid = "8acba7e7-2e50-4490-8328-b78a30472508")
OBISClient.occurrence(; nodeid = "4bf79a01-65a9-4db6-b37b-18434f26ddfc", limit = 100)
OBISClient.occurrence(; instituteid = 6223, limit = 100)
```

For a rectangle, `OBISClient.bbox(west, south, east, north)` writes the WKT and closes the
ring; a box with `west > east` crosses the antimeridian and comes back as a `MULTIPOLYGON`.
Build any other shape interactively at [wktmap.com](https://wktmap.com).
The package checks the WKT before sending it, because the API answers unparseable geometry
with an empty result set and no error.

### Selecting record classes

`absence`, `dropped` and `event` take `:exclude` (the default), `:include`, or `:only`.
These are three different questions, which is why they are not booleans.

```julia
OBISClient.occurrence("Abra alba"; absence = :only)      # only absences
OBISClient.occurrence("Abra alba"; absence = :include)   # presences and absences together
OBISClient.occurrence("Abra alba"; dropped = :only)      # records the QC pipeline dropped
```

### Filtering on quality flags

```julia
OBISClient.occurrence("Abra alba"; exclude = "ON_LAND", limit = 1000)   # drop the flagged ones
OBISClient.occurrence("Abra alba"; flags = "ON_LAND", limit = 100)      # inspect only those
OBISClient.occurrence("Abra alba"; exclude = ["ON_LAND", "NO_DEPTH"])
```

Either case works, since the package normalizes to the upper-case forms the API matches
on.
See [Interpreting OBIS data](interpreting.md) for what the flags mean.

## Working with a result

A result is an [`OBISClient.OBISTable`](@ref): column-oriented, typed, and Tables.jl-compatible.

```julia
recs = OBISClient.occurrence("Abra alba"; limit = 500)

OBISClient.nrow(recs)
OBISClient.ncol(recs)

recs.scientificName        # by property
recs[:decimalLatitude]     # by name
Tables.columnnames(recs)
Tables.schema(recs)

for row in Tables.rows(recs)
    row.scientificName, row.decimalLatitude
end
```

Columns are concretely typed. Coordinates and depths are `Float64` even though the API
encodes whole values as integers; the interpreted dates are `DateTime`; flags are a
`Set{String}`, empty when no flags were raised, so membership tests need no missing
handling.

```julia
count(fs -> "ON_LAND" in fs, recs.flags)
extrema(skipmissing(recs.decimalLatitude))
```

### Fields outside the core schema

Providers supply Darwin Core terms beyond the core schema, and which of them appear depends
on the query. They are kept per row in `extra` instead of becoming columns, so the main
schema stays the same between queries.

```julia
OBISClient.extra_names(recs)                    # what is present in this result
OBISClient.extra_column(recs, :waterBody)       # lift one out, missing where absent

using DataFrames
DataFrame(recs; flatten_extra = true)     # or flatten them all
```

### Provenance

```julia
meta = OBISClient.metadata(recs)
meta.accessed      # the date to cite
meta.total         # how many records matched, which may exceed what you retrieved
meta.params        # the query, as sent
```

## Other endpoints

```julia
# Which taxa occur here?
OBISClient.checklist(; geometry = "POLYGON ((2.3 51.8, 2.3 51.6, 2.6 51.6, 2.6 51.8, 2.3 51.8))")
OBISClient.checklist_redlist(; areaid = 259)

# Taxonomy.
OBISClient.taxon(141433)
OBISClient.taxon("Abra alba")

# Datasets, nodes, institutes, areas, countries.
OBISClient.dataset("Abra alba")
OBISClient.node()
OBISClient.institute("Abra alba")
OBISClient.area()
OBISClient.country()

# Counts, without retrieving records.
OBISClient.statistics("Abra alba")
OBISClient.statistics_years("Abra alba")
OBISClient.statistics_qc("Abra alba")
OBISClient.facet("datasetName"; scientificname = "Abra alba")
```

`statistics` accepts the same filters as `occurrence` and counts exactly the records that
query would return, which makes it the cheap way to size a query first.

### Maps without the records

Three endpoints aggregate on the server, so mapping a query of any size costs one request:

```julia
g = OBISClient.occurrence_grid("Abra alba"; precision = 3)   # records per geohash cell
g.longitude, g.latitude, g.records                             # cell centres and counts

OBISClient.occurrence_points("Abra alba")     # distinct occupied locations, no counts
OBISClient.occurrence_centroid("Abra alba")   # (longitude = …, latitude = …), or nothing
```

`precision` runs from 1 (45° cells) to 12 (cells of a few centimetres). They take the
`occurrence` filters except `dropped`, which these endpoints silently ignore, so passing
it raises an error instead. The grid and points endpoints return at most 100,000 features
and say nothing when they truncate; the package logs a warning when a result reaches that
size.

## Errors

The API reports most failures with a success status, so the package raises them instead.

```julia
OBISClient.occurrence("Abra albaa")     # OBISNameNotFoundError, not an empty result
OBISClient.occurrence(; geometry = "NOTWKT")   # OBISValidationError, caught locally
```

An empty result from this package therefore means no records matched. It does not mean the
query was malformed. Every error type is a subtype of [`OBISClient.OBISError`](@ref).

## Configuration

```julia
OBISClient.configure!(
    page_size = 10_000,        # fewer, larger requests on a long pull
    progress = true,           # progress while paginating
    request_gap = 0.5,         # seconds between requests
    retries = 8,
)
OBISClient.config()
```

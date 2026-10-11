# OBISClient.jl

A Julia client for [OBIS](https://obis.org), the Ocean Biodiversity Information System,
a programme of the Intergovernmental Oceanographic Commission of UNESCO.

[![Tests](https://github.com/dantebertuzzi/OBISClient.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/dantebertuzzi/OBISClient.jl/actions/workflows/CI.yml)
[![Coverage](https://codecov.io/gh/dantebertuzzi/OBISClient.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/dantebertuzzi/OBISClient.jl)
[![Julia](https://img.shields.io/badge/julia-1.10%2B-9558B2.svg?logo=julia&logoColor=white)](https://julialang.org)
[![Docs (stable)](https://img.shields.io/badge/docs-stable-blue.svg)](https://dantebertuzzi.github.io/OBISClient.jl/stable)
[![Docs (dev)](https://img.shields.io/badge/docs-dev-lightblue.svg)](https://dantebertuzzi.github.io/OBISClient.jl/dev)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/dantebertuzzi/OBISClient.jl)

> **Not an official OBIS product.** This is an independent, community-maintained client,
> not affiliated with or endorsed by OBIS, the IOC, or UNESCO. The data, the API and the
> quality control behind them are the work of OBIS and its nodes.

**Documentation: [dantebertuzzi.github.io/OBISClient.jl/stable](https://dantebertuzzi.github.io/OBISClient.jl/stable)**

Nothing to install to try it: Google Colab runs Julia natively. The badge above opens the
repository's notebook list, so you pick which one to run; each also carries its own badge below.
Pick the Julia runtime under *Runtime ▸ Change runtime type* and run the cells. All three are
committed with the outputs of a real run, so they also read on GitHub without being executed.

| Notebook | What it does |
|---|---|
| [`getting-started.ipynb`](notebooks/getting-started.ipynb) [![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/dantebertuzzi/OBISClient.jl/blob/main/notebooks/getting-started.ipynb) | A first query and what comes back: the stable schema, the licences and citations carried on a result, the quality flags and what a default query filters out, records per year, a scatter of coordinates with the `ON_LAND` records marked, and `estimate_size` before a large pull. |
| [`obis-missingness.ipynb`](notebooks/obis-missingness.ipynb) [![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/dantebertuzzi/OBISClient.jl/blob/main/notebooks/obis-missingness.ipynb) | What is *absent* from a pull of records, read with [MissingPatterns.jl](https://github.com/dantebertuzzi/MissingPatterns.jl): two depth fields that turn out to be one, a provenance split hiding in a negative ϕ, not a single complete record in three thousand, and a check of the sample against OBIS's own counts for the whole query. Also in that package's repository, since it belongs to both. |
| [`descriptive-statistics.ipynb`](notebooks/descriptive-statistics.ipynb) [![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/dantebertuzzi/OBISClient.jl/blob/main/notebooks/descriptive-statistics.ipynb) | Describing a pull before modelling it, with CairoMakie figures on the palette the package's own maps use: centre, spread and skew side by side, a multimodal temperature distribution resolved into one curve per contributing dataset, depth as an ECDF split by `basisOfRecord`, the categorical columns with their absences counted, a rank-correlation matrix where the latitude–temperature gradient has been erased by mixing two ocean basins, and a check of the sample against OBIS's own counts for the whole query. |

## Installation

```julia
using Pkg
Pkg.add("OBISClient")
```

## A first query

```julia
using OBISClient

recs = OBISClient.occurrence("Abra alba"; limit = 500)

recs.scientificName          # a column
recs.decimalLatitude         # Vector{Union{Missing,Float64}}
recs.flags                   # a Set{String} per record

OBISClient.nrow(recs)
```

Results implement Tables.jl, so they go where you need them:

```julia
using DataFrames
df = DataFrame(recs)

using CSV
CSV.write("abra_alba.csv", recs)
```

Filters combine, and take Julia types where OBIS takes strings:

```julia
using Dates

recs = OBISClient.occurrence(;
    scientificname = "Abra alba",
    geometry  = "POLYGON ((2.0 52.5, 2.0 51.0, 4.5 51.0, 4.5 52.5, 2.0 52.5))",
    startdate = Date(2000, 1, 1),
    enddate   = Date(2020, 12, 31),
)
```

`OBISClient.bbox(2.0, 51.0, 4.5, 52.5)` writes the same rectangle without the hand-closed
ring, and splits a box across the antimeridian into a `MULTIPOLYGON`.

To map a query without retrieving it, OBIS aggregates on the server:

```julia
g = OBISClient.occurrence_grid("Abra alba"; precision = 3)   # records per geohash cell
OBISClient.occurrence_centroid("Abra alba")                  # (longitude = …, latitude = …)
```

See [Getting started](https://dantebertuzzi.github.io/OBISClient.jl/stable/getting-started/)
for the full filter set and the other endpoints.

## Licences and citations

OBIS data comes with conditions. Licences vary by dataset, and any use has to be cited with
the date it was accessed. Both travel with the result, so you can check them before you
build anything:

```julia
rights = OBISClient.licenses(recs)      # what the result permits, per licence
print(OBISClient.citations(recs; format = :text))
write("obis-references.bib", OBISClient.citations(recs; format = :bibtex))
```

One query usually spans several datasets, and the most restrictive licence governs the
whole. Where a provider's rights statement can't be identified, it is reported as
`unknown`. The package does not assume it is permissive.

[Licensing and citation](https://dantebertuzzi.github.io/OBISClient.jl/stable/licensing/)
covers the data policy and shows the rights summary laid out with PrettyTables.

## Large queries and the bulk export

For big volumes OBIS recommends its GeoParquet export over the API. A query estimated to
exceed the configured limit raises an error listing your options instead of switching
routes quietly, since the two don't return the same thing: the export is a periodic
snapshot, the API is live.

```julia
using OBISClient, DuckDB          # DuckDB loads the extension that reads the files

paths = OBISClient.download_exports(; datasetid = "0c44a7dc-7f06-4eab-b831-4cae103c9902",
                                    dir = "obis-export")
recs = OBISClient.read_export(paths)
```

`read_export` maps the export's 622-column schema onto the same table an API query returns,
rights and citations included, so `licenses`, `citations` and `DataFrame` all work on it
unchanged. To stream a query instead, `occurrence_pages` yields one page at a time and its
cursor is a single string you can save and resume from.

More in [Large queries](https://dantebertuzzi.github.io/OBISClient.jl/stable/large-queries/).

## What the data looks like

Figures come from [`examples/figures.jl`](examples/figures.jl), run against live queries.
Plotting isn't part of the package; CairoMakie and GeoMakie belong to the example
environment.

A default query returns flagged records alongside clean ones. The `ON_LAND` records here
sit on the Dutch coast and in the Zeeland estuaries, which is what a georeferencing error
looks like for a marine bivalve.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="examples/figures/map-north-sea-dark.png">
  <img alt="Occurrences of Abra alba in the southern North Sea, with records flagged ON_LAND shown separately" src="examples/figures/map-north-sea.png">
</picture>

Record counts track sampling effort. The rise through the late twentieth century is survey
programmes and digitization campaigns; the fall at the recent end is publication lag.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="examples/figures/records-per-year-dark.png">
  <img alt="Records of Abra alba per year worldwide, rising steeply from the 1970s and falling at the recent end" src="examples/figures/records-per-year.png">
</picture>

Two longer examples are written up in the manual:
[killer whales](https://dantebertuzzi.github.io/OBISClient.jl/stable/worked-example/)
([`examples/orcas.jl`](examples/orcas.jl)) and
[the Brazilian shelf](https://dantebertuzzi.github.io/OBISClient.jl/stable/mapping-a-coast/)
([`examples/brazil.jl`](examples/brazil.jl)).

## Design

A few decisions you'll notice in daily use, covered at length under
[What the package guarantees](https://dantebertuzzi.github.io/OBISClient.jl/stable/#What-the-package-guarantees)
and [Internals](https://dantebertuzzi.github.io/OBISClient.jl/stable/internals/):

- **The schema is stable.** OBIS returns only the fields a record has values for, so the
  field set shifts from query to query. Results here always have the same columns, in the
  same order, with concrete element types. Darwin Core fields outside that schema are kept
  per row in an `extra` column.
- **`missing` means missing.** Collection-valued columns are never `missing`: `flags` is an
  empty `Set{String}` when nothing was raised, so `count(fs -> "ON_LAND" in fs, recs.flags)`
  needs no missing-handling.
- **Tables.jl is the interface.** Installing the client pulls in HTTP, JSON3, StructTypes,
  Tables and two stdlibs. DataFrames and DuckDB support live in package extensions that
  load only if you already have them.
- **Requests are conservative.** Serial, identified by a `User-Agent` naming the package and
  this repository, with exponential backoff that honours `Retry-After`. OBIS asks that
  downloads not be parallelized, so the package doesn't offer it.
- **Responses can be cached.** OBIS ingests continuously, so re-running an analysis months
  later otherwise gives you different data. See
  [Reproducibility](https://dantebertuzzi.github.io/OBISClient.jl/stable/reproducibility/).

## Scope

This is a client, and only that. It doesn't analyse, model, or draw anything, and it ships
no OBIS data: a frozen copy inside a package would break the citation it's meant to
support.

## Before you analyse anything

Two things bear on any result, both covered in
[Interpreting OBIS data](https://dantebertuzzi.github.io/OBISClient.jl/stable/interpreting/):
record counts measure sampling effort as much as biology, and the default view is filtered
(quality-flagged records are in, dropped records are out, absences are excluded unless you
ask for them).

OBIS states the general caution itself:

> Appropriate caution is necessary in the interpretation of results derived from OBIS.
> Users must recognize that the analysis and interpretation of data require background
> knowledge and expertise about marine biodiversity (including ecosystems and taxonomy).

`OBISClient.disclaimer()` prints it in full.

## Citing

Cite the datasets you used; `OBISClient.citations(result)` builds them with the access date
filled in. Where a result draws on many datasets, the database as a whole may be cited in
addition to the individual datasets, though not in place of them, with
`OBISClient.obis_citation(...)`. See [manual.obis.org/citing.html](https://manual.obis.org/citing.html).

If the package itself was useful, [CITATION.cff](CITATION.cff) says how to cite it. That
doesn't replace citing the data.

## Acknowledgements

OBIS is built by its secretariat, its regional and thematic nodes, and the thousands of
providers who publish observations through them. The data, the quality control, the
taxonomy matching against WoRMS and the infrastructure serving it are all their work.

## License

MIT for the package; see [LICENSE](LICENSE). The data it retrieves is licensed by its
providers, under the terms each result reports.

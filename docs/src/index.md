# OBISClient.jl

A Julia client for OBIS, the Ocean Biodiversity Information System, a programme of the
Intergovernmental Oceanographic Commission of UNESCO. Results come back as typed tables
with a fixed schema, carrying the licence and citation of the dataset each row came from.

!!! note "Not an official OBIS product"
    OBISClient.jl is an independent, community-maintained client. It is not affiliated with,
    endorsed by, or maintained by OBIS, the Intergovernmental Oceanographic Commission, or
    UNESCO. The name identifies the service the package connects to; the data, the API and
    the quality control pipeline are the work of OBIS and its nodes.

## Installation

```julia
using Pkg
Pkg.add("OBISClient")
```

## Quick start

```julia
using OBISClient

recs = OBISClient.occurrence("Abra alba"; limit = 500)

recs.scientificName        # a column
recs.decimalLatitude       # Float64, always
recs.flags                 # a Set{String} per record

OBISClient.licenses(recs)        # may these data be redistributed?
OBISClient.citations(recs)       # how to credit them, access date included
```

Results implement the Tables.jl interface, so `DataFrame(recs)`, `CSV.write("out.csv", recs)`,
Arrow and Parquet all work without the package depending on any of them.

## Functions

| Function | What it returns | Page |
| --- | --- | --- |
| [`occurrence`](@ref OBISClient.occurrence) | Occurrence records, as a typed table | [Getting started](getting-started.md) |
| [`occurrence_pages`](@ref OBISClient.occurrence_pages) | Lazy, resumable pages of the same | [Large queries](large-queries.md) |
| [`occurrence_by_id`](@ref OBISClient.occurrence_by_id) | One record, by OBIS record UUID | [Getting started](getting-started.md) |
| [`checklist`](@ref OBISClient.checklist) | Which taxa occur in a selection | [Getting started](getting-started.md) |
| [`taxon`](@ref OBISClient.taxon) | A WoRMS taxon, by AphiaID or exact name | [Getting started](getting-started.md) |
| [`dataset`](@ref OBISClient.dataset) | Dataset metadata, including the rights statement | [Licensing and citation](licensing.md) |
| [`node`](@ref OBISClient.node), [`institute`](@ref OBISClient.institute), [`area`](@ref OBISClient.area), [`country`](@ref OBISClient.country) | The identifiers the filters accept | [Getting started](getting-started.md) |
| [`statistics`](@ref OBISClient.statistics) | Counts for a query, without retrieving records | [Interpreting OBIS data](interpreting.md) |
| [`statistics_years`](@ref OBISClient.statistics_years) | Records per year | [Interpreting OBIS data](interpreting.md) |
| [`statistics_qc`](@ref OBISClient.statistics_qc) | Missing and invalid fields, on-land, non-marine | [Interpreting OBIS data](interpreting.md) |
| [`facet`](@ref OBISClient.facet) | Counts grouped by a field | [Interpreting OBIS data](interpreting.md) |
| [`licenses`](@ref OBISClient.licenses) | What a result may be used for | [Licensing and citation](licensing.md) |
| [`citations`](@ref OBISClient.citations) | The credit a result requires, as a table, text or BibTeX | [Licensing and citation](licensing.md) |
| [`estimate_size`](@ref OBISClient.estimate_size) | How many records a query would return | [Large queries](large-queries.md) |
| [`download_exports`](@ref OBISClient.download_exports) | The bulk GeoParquet route | [Large queries](large-queries.md) |
| [`QueryCache`](@ref OBISClient.QueryCache) | Reproducible re-runs against cached responses | [Reproducibility](reproducibility.md) |
| [`configure!`](@ref OBISClient.configure!) | Page size, pacing, retries, caching | [Getting started](getting-started.md) |

[Worked example: killer whales](worked-example.md) works through a full session: retrieve,
map, group, pivot, and test a relationship.

Full docstrings are in the [Public API](api.md) reference. Functions the package uses
internally, and that the schema is built from, are in [Internals](internals.md).

## What the package guarantees

**The schema does not move.** OBIS returns only the fields a record has a value for, so the
field set differs from query to query. A result here always has the same columns in the
same order, with concrete types and `missing` for absent values. Darwin Core fields outside
the core schema are preserved per row in an `extra` column.

**Every row carries its rights.** The licence and citation of the dataset a record came
from travel with the record, and the result records the date it was retrieved. The OBIS
citation format requires that date, and nothing in the data supplies it.

**You can reach what the default view omits.** Absence records and records dropped by the
quality pipeline are excluded unless asked for. The tri-state `absence`, `dropped` and
`event` keywords ask for them.

**The choice of access route stays yours.** A query too large for the API raises an error
listing the alternatives instead of switching routes on its own, because the API and the
bulk export do not cover the same records.

## Read this before analysing anything

Record counts measure sampling effort as much as biology, and the default view of OBIS is
filtered in two directions. [Interpreting OBIS data](interpreting.md) covers what turns a
correct query into a wrong conclusion.

```@raw html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/records-per-year-dark.png">
  <img alt="Records of Abra alba per year worldwide" src="assets/records-per-year.png">
</picture>
```

## How this manual was checked

The numbers, field names and error messages here come from the live OBIS API rather than
from its documentation. Where a statement rests on observation rather than on something
OBIS publishes, the text says so.

Output in the examples was pasted back from actual runs. Docstring examples marked
`jldoctest` run on every documentation build. An
[integration suite](https://github.com/dantebertuzzi/OBISClient.jl/blob/main/test/integration/runtests.jl)
and a [link check](https://github.com/dantebertuzzi/OBISClient.jl/blob/main/test/links/runtests.jl)
run weekly against the live API and over every URL in the manual and the docstrings.

The figures come from [`examples/figures.jl`](https://github.com/dantebertuzzi/OBISClient.jl/blob/main/examples/figures.jl)
and [`examples/orcas.jl`](https://github.com/dantebertuzzi/OBISClient.jl/blob/main/examples/orcas.jl),
which query the API when they run. Counts in the figures move as OBIS ingests data.

## Sources

This manual describes the package. For the service and the data behind it:

| Source | What it covers |
| --- | --- |
| [api.obis.org](https://api.obis.org/) | The API specification (`obis_v3.yml`) |
| [manual.obis.org/access.html](https://manual.obis.org/access.html) | How OBIS data can be accessed, and what each route includes |
| [manual.obis.org/policy.html](https://manual.obis.org/policy.html) | The data policy: licences, conditions of use, the disclaimer |
| [manual.obis.org/citing.html](https://manual.obis.org/citing.html) | Citation formats |
| [manual.obis.org/dataquality.html](https://manual.obis.org/dataquality.html) | Quality flags and the QC pipeline |
| [github.com/iobis/obis-qc](https://github.com/iobis/obis-qc) | Each quality check and the flag it raises |
| [github.com/iobis/obis-open-data](https://github.com/iobis/obis-open-data) | The bulk GeoParquet export on AWS |
| [dwc.tdwg.org/terms](https://dwc.tdwg.org/terms/) | The Darwin Core standard |

The repository also carries [`NOTES.md`](https://github.com/dantebertuzzi/OBISClient.jl/blob/main/NOTES.md),
the research notes the package was built from: the endpoint and parameter inventory, the
response shapes, the pagination and error semantics, and which statements are documented
versus observed.

## Scope

The package is a client. It does not model, plot, or ship data. Analysis belongs in
packages built for it, and OBIS records carry a DOI and an access date that a frozen copy
inside a package would misreport.

## How to cite

Cite the **datasets you used**. `OBISClient.citations(result)` builds those, with the access
date filled in; see [Licensing and citation](licensing.md). Citing the package does not
replace citing the data.

For the package itself, the repository ships a
[`CITATION.cff`](https://github.com/dantebertuzzi/OBISClient.jl/blob/main/CITATION.cff), which
GitHub's "Cite this repository" button reads, and a
[`CITATION.bib`](https://github.com/dantebertuzzi/OBISClient.jl/blob/main/CITATION.bib):

```bibtex
@software{bertuzzi_obis_jl_2026,
  author  = {Bertuzzi, Dante},
  title   = {{OBISClient.jl}: a {Julia} client for the {Ocean} {Biodiversity}
             {Information} {System}},
  year    = {2026},
  version = {0.2.0},
  url     = {https://github.com/dantebertuzzi/OBISClient.jl},
  note    = {Julia package}
}
```

Cite the version you actually ran. What you get back depends on the release and on the
state of OBIS the day you queried it; the access date on your data citations covers the
second half of that.

"""
    OBISClient

A Julia client for OBIS, the Ocean Biodiversity Information System, a programme of the
Intergovernmental Oceanographic Commission of UNESCO.

Results are Tables.jl tables with a fixed, concretely typed schema, and they carry the
licence and citation of every dataset they draw on together with the date they were
retrieved.

!!! note "Not an official OBIS product"
    This is an independent, community-maintained client. It is not affiliated with,
    endorsed by, or maintained by OBIS, the Intergovernmental Oceanographic Commission, or
    UNESCO. The name contracts Ocean Biodiversity Information System, the service the
    package connects to; the General registry does not accept `OBIS` itself, being four
    characters and all upper case.

# Getting started

```julia
using OBISClient, DataFrames

recs = OBISClient.occurrence("Abra alba"; limit = 1000)
df = DataFrame(recs)

OBISClient.licenses(recs)                        # may these data be redistributed?
print(OBISClient.citations(recs; format = :text))  # how to credit them
```

# Interpreting the results

Record counts measure sampling effort as much as biology, and the default view of OBIS
excludes two classes of record that change what a result means. See the "Interpreting OBIS
data" section of the documentation, and the disclaimer in [`OBIS_DISCLAIMER`](@ref), before
drawing conclusions.
"""
module OBISClient

using Dates
using Dates: DateTime, Date, today, now, UTC
using HTTP
using JSON3
using SHA
using StructTypes
using Tables

# Core plumbing, in dependency order.
include("errors.jl")
include("config.jl")
include("flags.jl")
include("params.jl")
include("cache.jl")
include("http.jl")
include("schema.jl")
include("table.jl")
include("license.jl")
include("pagination.jl")

# Endpoints.
include("occurrence.jl")
include("dataset.jl")
include("endpoints.jl")
include("statistics.jl")
include("spatial.jl")
include("citation.jl")
include("export.jl")

"""
    OBIS_DISCLAIMER

The interpretation disclaimer from the OBIS data policy, reproduced verbatim.

Printed by [`disclaimer`](@ref).
"""
const OBIS_DISCLAIMER = """
Appropriate caution is necessary in the interpretation of results derived from OBIS. Users
must recognize that the analysis and interpretation of data require background knowledge
and expertise about marine biodiversity (including ecosystems and taxonomy). Users should
be aware of possible errors, including in the use of species names, geo-referencing, data
handling, and mapping. They should cross check their results for possible errors and
qualify their interpretation of any results accordingly.

Unless data are collected through activities funded by IOC/IODE, neither UNESCO, IOC, IODE,
the OBIS Secretariat, nor its employees or contractors, own the data in OBIS and they take
no responsibility for the quality of data or products based on OBIS, or its use or misuse.
"""

"""
    disclaimer()

Print the OBIS interpretation disclaimer.
"""
function disclaimer()
    println(OBIS_DISCLAIMER)
    return nothing
end

function __init__()
    isempty(CONFIG.user_agent) && (CONFIG.user_agent = default_user_agent())
    return nothing
end

# Queries.
export occurrence, occurrence_pages, occurrence_by_id
export occurrence_grid, occurrence_points, occurrence_centroid, bbox
export checklist, checklist_redlist, checklist_newest
export taxon, taxon_annotations
export dataset, dataset_by_id, dataset_errors
export node, node_activities, institute, institute_by_id, area, country
export facet,
    statistics, statistics_years, statistics_env, statistics_qc,
    statistics_composition
export metrics, metrics_downloads

# Rights and provenance.
export citations, licenses, obis_citation

# Results.
#
# `nrow`, `ncol` and `metadata` are deliberately not exported: DataFrames exports the same
# names through DataAPI, and exporting them here would make `using OBISClient, DataFrames` an
# ambiguity error at every call site. Reach them as `OBISClient.nrow(t)`, or load the DataFrames
# extension, which makes the DataAPI versions work on an `OBISTable` directly.
export OBISTable, extra_names, extra_column, cursor

# Configuration and errors.
export configure!, config, QueryCache, clear_cache!, cache_entries
export OBISError, OBISValidationError, OBISAPIError, OBISNameNotFoundError,
    OBISConnectionError, OBISLargeQueryError

# Access routes.
export estimate_size,
    export_url, export_covers, download_export, download_exports,
    export_licenses, read_export

end # module

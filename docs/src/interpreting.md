# Interpreting OBIS data

OBIS aggregates observations that thousands of people collected for their own purposes,
over two centuries, with methods that were never coordinated. The records are real. What
they add up to is a harder question. This page covers what most often turns a correct
query into a wrong conclusion.

OBIS states the general caution itself, in its data policy:

> Appropriate caution is necessary in the interpretation of results derived from OBIS.
> Users must recognize that the analysis and interpretation of data require background
> knowledge and expertise about marine biodiversity (including ecosystems and taxonomy).
> Users should be aware of possible errors, including in the use of species names,
> geo-referencing, data handling, and mapping. They should cross check their results for
> possible errors and qualify their interpretation of any results accordingly.

Print it in full with [`OBISClient.disclaimer`](@ref).

## Record counts measure sampling effort

This is the mistake with the largest consequences, because the resulting numbers look like
biology.

A record exists because somebody looked, identified what they found, and published it. The
number of records for a taxon in a place and year is therefore the product of how much of
it there was and how hard people looked. Across the history of OBIS, the second factor
varies by orders of magnitude more than the biology does.

You can see the shape of it directly:

```julia
using OBISClient

years = OBISClient.statistics_years("Abra alba")

for e in years
    e["year"] >= 1960 || continue
    e["year"] % 10 == 0 || continue
    println(e["year"], "  ", lpad(e["records"], 6), "  ", "▪"^(e["records"] ÷ 200))
end
```


```@raw html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/records-per-year-dark.png">
  <img alt="Records of Abra alba per year worldwide" src="../assets/records-per-year.png">
</picture>
```

The series for almost any well-recorded taxon rises steeply through the late twentieth
century and then moves sharply with individual events. Those movements are survey
programmes starting and ending, museum collections being digitized, and national nodes
joining OBIS and contributing decades of backlog in a single year. *Abra alba* has records
from 1841 onward, and the global OBIS year range starts in 1103, which says more about
when people began collecting than about the ocean.

Three consequences:

- **A time series of record counts is not an abundance trend.** Two taxa in the same region
  can have opposite record trends because one is monitored by a long-running programme and
  the other is not.
- **A map of record density is a map of survey coverage.** Coastal Europe and North America
  are dense; the open ocean and the southern hemisphere are sparse. That is a statement
  about ships and funding.
- **Comparisons need a denominator.** If you must compare, compare against the total
  records from the same datasets, region and period. That total is the effort that
  produced them:

```julia
target = OBISClient.statistics("Abra alba"; areaid = 259)["records"]
effort = OBISClient.statistics(; areaid = 259)["records"]
share  = target / effort
```

That is still crude, but a proportion of a sampled community tells you more than a raw
count does.
Properly accounting for effort is a modelling problem, which is outside this package's
scope.

## The default view is filtered in two directions

A default query does not return everything OBIS holds about a taxon. Two classes of record
are excluded, and they are excluded for different reasons.

### Dropped records

OBIS runs a quality pipeline over everything it ingests. Records failing certain checks are
**dropped** from the main index: missing or impossible coordinates, coordinates at exactly
zero, and names that cannot be matched to the World Register of Marine Species, or that
match a taxon WoRMS considers exclusively freshwater or terrestrial.

```julia
OBISClient.DROPPING_FLAGS
```

Dropped records are not deleted, only hidden by default. They are the record of what went
wrong, and they are worth looking at when a dataset returns fewer records than expected:

```julia
dropped = OBISClient.occurrence("Abra alba"; dropped = :only)

# Why were they dropped?
using DataFrames
counts = Dict{String,Int}()
for fs in dropped.flags, f in fs
    counts[f] = get(counts, f, 0) + 1
end
sort(collect(counts); by = last, rev = true)
```

A large `NO_MATCH` count usually means a naming or `scientificNameID` problem in the source
dataset rather than anything about the organisms.

### Absence records

An **absence** record says a species was looked for at a place and time and not found. OBIS
marks a record as an absence when `occurrenceStatus` is `absent`, or when `individualCount`
is zero.

This is a different kind of information from a presence, and analytically it is often the
scarcer half. For *Abra alba*, the absences number roughly a quarter again of the presences,
across fourteen datasets:

```julia
OBISClient.statistics("Abra alba")["records"]                      # presences
OBISClient.statistics("Abra alba"; absence = :only)["records"]      # absences
OBISClient.statistics("Abra alba"; absence = :include)["records"]   # both
```

Absence records are excluded from the default view on either access route, and asked for
with `absence = :include` or `:only`. OBIS's data access page says the Mapper downloads and
the bulk export contain none at all; for the bulk export that is stale: the files do carry
them, verified count for count against `/statistics` (NOTES.md §7.3), and OBIS has confirmed
they are there deliberately ([iobis/manual#127](https://github.com/iobis/manual/issues/127)), and
[`OBISClient.read_export`](@ref) reads them with the same tri-state selection the API takes. The
Mapper was not checked, so treat the page's statement about it as it stands.

Why it matters: a presence-only dataset cannot distinguish "not recorded here" from "looked
for and not found here". Most methods need a contrast between occupied and unoccupied
sites, and they have to build the unoccupied set somehow, usually as pseudo-absences drawn
from the background. That construction is an assumption about where the species is absent.
A recorded absence is an observation, so using one where it exists takes that assumption
out of the analysis.

```julia
# Presences and absences together, labelled.
both = OBISClient.occurrence("Abra alba"; absence = :include, limit = 5000)
count(both.absence)          # how many are absences
```

## Quality flags are attached to records you do get

Flags do not remove a record. `ON_LAND`, `NO_DEPTH`, `DEPTH_EXCEEDS_BATH`,
`NO_ACCEPTED_NAME` and the rest ride along on records that are returned normally, and
ignoring them silently accepts every problem they describe.

```julia
recs = OBISClient.occurrence("Abra alba"; limit = 5000)

# How many marine records are positioned on land?
count(fs -> "ON_LAND" in fs, recs.flags)

# Exclude them at the source instead.
clean = OBISClient.occurrence("Abra alba"; exclude = "ON_LAND", limit = 5000)
```

`ON_LAND` is a georeferencing error most of the time: a coordinate transposed, truncated,
or given as a locality centroid inland. For a habitat or distribution analysis those
records are actively misleading. Mapped, they cluster on the coast and in estuaries, in the
pattern a transposed or truncated coordinate produces:
```@raw html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/map-north-sea-dark.png">
  <img alt="Occurrences of Abra alba in the southern North Sea, with ON_LAND records shown separately" src="../assets/map-north-sea.png">
</picture>
```


Not every flag is an error, though, and no general rule covers the difference. You need to
know the domain.
`DEPTH_EXCEEDS_BATH` compares the recorded depth against GEBCO bathymetry, and OBIS notes
that a measured depth is sometimes more accurate than the gridded bathymetry it is checked
against. In a canyon or a trench, the flag can be the thing that is wrong.
`MARINE_UNSURE` reflects uncertainty in WoRMS about the taxon's habitat, not about the
observation.

The flags in `OBISClient.KNOWN_FLAGS` are the documented vocabulary, and the QC pipeline's own
reference at [github.com/iobis/obis-qc](https://github.com/iobis/obis-qc) defines each
check. OBIS adds checks over time, so the vocabulary is open: an unrecognized flag is
passed through with a warning instead of being rejected.

`statistics_qc` summarizes flags and missing fields for a whole query, which is a better
first move than inspecting records:

```julia
qc = OBISClient.statistics_qc("Abra alba")
qc["flags"]
qc["onland"]
```

### Flags are case-sensitive

The API matches flags in upper case. A lower-case flag is not an error: `flags = "on_land"`
returns zero records, and `exclude = "on_land"` applies no filter at all, both with a
success status. The package normalizes case for you, so either spelling works here. The
behaviour is worth knowing if you also query the API directly.

## Names are matched, not authoritative

`scientificName` in a result is the name OBIS matched against WoRMS, not necessarily the
name the provider wrote. The provider's original is kept as `originalScientificName`, and
the two differ whenever a synonym was resolved, a misspelling corrected, or a name updated.

```julia
recs = OBISClient.occurrence("Abra alba"; limit = 1000)
count(i -> recs.scientificName[i] != recs.originalScientificName[i], 1:OBISClient.nrow(recs))
```

Querying by `taxonid` (an AphiaID) rather than by name avoids the ambiguity entirely, since
it addresses a WoRMS concept directly:

```julia
OBISClient.occurrence(; taxonid = 141433, limit = 100)     # Abra alba, unambiguously
```

Where a name could not be matched, records carry `NO_MATCH` and are dropped, and the WoRMS
team's notes on the name are available:

```julia
OBISClient.taxon_annotations(; scientificname = "Abra alba")
```

## A short checklist

Before drawing a conclusion from an OBIS query:

1. Have you looked at `statistics_qc` for the query?
2. Do you know whether absence records exist for this taxon, and whether you want them?
3. Have you decided what to do about each flag present?
4. If you are comparing counts across time or space, what is the denominator?
5. Are you citing the datasets, and do their licences permit what you plan to do?
   See [Licensing and citation](licensing.md).

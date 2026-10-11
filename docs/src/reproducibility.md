# Reproducibility

OBIS ingests records continuously. Datasets are added, corrected and re-harvested, and the
quality pipeline is updated. The same query run twice returns different data, and the
difference grows with time.

That is a problem for anything published. A figure in a paper is the output of a query
against a database that no longer exists in that state, and nothing in the data records
which state that was.

## Caching raw responses

An optional local cache stores each raw response, addressed by a hash of the query, with
the retrieval date and the response `ETag`:

```julia
using OBISClient

OBISClient.configure!(cache = OBISClient.QueryCache("data/obis-cache"))

recs = OBISClient.occurrence("Abra alba"; limit = 5000)   # fetched and stored
again = OBISClient.occurrence("Abra alba"; limit = 5000)  # served from disk, no request
```

Entries never expire, since an expiring cache cannot answer "re-run this against the data
as it stood in March". Remove entries explicitly:

```julia
OBISClient.clear_cache!()
```

What is stored is the **raw response body**, not the parsed table, so a re-run reproduces
the original data even if the package's schema handling has changed in the meantime. The
stored artifact does not depend on this package's decisions.

The cache key covers the base URL, the endpoint and the parameters, sorted, so keyword
order does not matter:

```julia
OBISClient.occurrence("Abra alba"; startdepth = 5, limit = 100)
OBISClient.occurrence(; startdepth = 5, scientificname = "Abra alba", limit = 100)  # same entry
```

## Keeping the cache with the analysis

Put the cache in the project directory and commit it, or archive it alongside the results:

```julia
OBISClient.configure!(cache = OBISClient.QueryCache(joinpath(@__DIR__, "data", "obis-cache")))
```

The directory holds one `.json` response and one `.meta.json` per query. The metadata
records what was asked and when:

```julia
for e in OBISClient.cache_entries()
    println(e["endpoint"], "  ", e["accessed"], "  ", e["bytes"], " bytes")
    println("  ", e["parameters"])
end
```

## Guaranteeing a re-run uses the cache

A cache that silently falls back to the network guarantees nothing. Open it read-only and
any query that is not already cached fails loudly instead of fetching today's data:

```julia
OBISClient.configure!(cache = OBISClient.QueryCache("data/obis-cache"; readonly = true))

recs = OBISClient.occurrence("Abra alba"; limit = 5000)   # from disk

OBISClient.occurrence("Zostera marina")                    # OBISAPIError: not in the cache
```

This is the mode to use when re-running a published analysis: it turns "the numbers changed
and I do not know why" into an error naming the query that was not part of the original
run.

## Has the data changed since?

The cache keeps what you fetched; it does not say whether OBIS would still give you the
same thing. `revalidate_cache` asks, one conditional request per entry:

```julia
using DataFrames

report = OBISClient.revalidate_cache()
DataFrame(report)[:, [:endpoint, :parameters, :retrieved, :status]]
```

Each entry is sent with the `ETag` stored beside it. OBIS answers `304 Not Modified` with
no body when the response would be the same, so checking even a large cache costs little.
`status` is `:unchanged` or `:changed`, or `:skipped` for entries from another `base_url`
and `:failed` when a request did not go through.

Nothing is overwritten. The point of the cache is that the old data survives, and an analysis
re-run against it still reproduces the published numbers; the report tells you whether
re-running against today's OBIS would not. To move the cache to the current data
deliberately, for a new version of an analysis:

```julia
OBISClient.revalidate_cache(; update = true)   # replaces every entry that changed
```

A read-only cache can be checked but not updated.

## Citing what you actually used

The access date belongs to the request, so the citation should carry the date the data was
retrieved, not the date the script was last run. Read it from the cache:

```julia
for e in OBISClient.cache_entries()
    println(e["endpoint"], " accessed ", e["accessed"])
end
```

A dataset DOI, where the provider registered one, is a stable pointer to the source
independent of OBIS's current state, and is included in the citation output:

```julia
cites = OBISClient.citations(recs)
collect(skipmissing(cites.doi))
```

See [Licensing and citation](licensing.md).

## What caching does not give you

The cache pins the *responses*, not the OBIS database. `revalidate_cache` tells you *that*
a response changed upstream, not what changed in it, and the cache cannot reconstruct a
query you never ran. If reproducibility matters for a
piece of work:

- cache every query the analysis makes, from the start;
- keep the cache directory with the code;
- record the access date in the manuscript, which the citations already do;
- and where a dataset has a DOI, cite it, so a reader can reach the source directly.

For a frozen snapshot of the whole database, as opposed to one of your queries, OBIS
publishes dated bulk exports; see [Large queries](large-queries.md).

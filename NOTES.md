# OBIS API notes

Research notes on the OBIS (Ocean Biodiversity Information System) web service, written
before implementing the client. This document describes the service: its endpoints,
parameters, response shapes, pagination behavior, error semantics, and the licensing and
citation rules that apply to the data.

Everything recorded here was verified against the live service. Statements that come from
observation rather than from documentation are marked **(observed)**, together with the
probe that produced them, so they can be re-checked when the API changes.

Probed on 2026-09-06 against `https://api.obis.org/v3/`.

## Sources

| Source | URL |
| --- | --- |
| OpenAPI specification | `https://api.obis.org/obis_v3.yml` (linked from the Swagger UI at `https://api.obis.org/`) |
| Data access chapter | https://manual.obis.org/access.html |
| Data policy | https://manual.obis.org/policy.html |
| Citation guidance | https://manual.obis.org/citing.html |
| Data quality flags | https://manual.obis.org/dataquality.html |
| Darwin Core chapter | https://manual.obis.org/darwin_core.html |
| Darwin Core terms | https://dwc.tdwg.org/terms/ and `https://github.com/tdwg/dwc` (`vocabulary/term_versions.csv`) |
| QC pipeline reference | https://github.com/iobis/obis-qc |
| Full exports on AWS Open Data | https://github.com/iobis/obis-open-data |
| Export field reference | https://obis.org/data/access/ |

There is no `/openapi.json`; that path returns 404. The Swagger UI at the API root loads
`obis_v3.yml`, which is the specification document and the source of truth for endpoint
and parameter names.

## 1. Service shape

- Base URL: `https://api.obis.org/v3/`. The version is part of the path; the spec declares
  no other server.
- No authentication, no API key.
- Responses are JSON (`application/json; charset=utf-8`), except the tile, KML, and MVT
  endpoints.
- `gzip` is supported and worth requesting on every call. **(observed:
  `Accept-Encoding: gzip` on `/occurrence?size=100` returns `Content-Encoding: gzip`.)**
- Responses carry a weak `ETag` and pass through a cache layer (`X-Cache-Status`,
  `X-Cache-Date`). **(observed on `/statistics`.)** Useful for conditional revalidation of
  a local cache, and it works: `If-None-Match` with the stored tag returns
  `304 Not Modified` on `/statistics` and `/occurrence`, with or without gzip, and a
  mismatched tag returns 200. The tag is content-derived — its hex prefix is the body length
  (`W/"1522-…"` on a 5,410-byte body) — so a 304 means the body is unchanged. **(observed
  2026-10-10.)**
- There are no rate-limit headers and no API-version header in the response. There is no
  documented request quota.

## 2. Endpoints

### 2.1 Endpoints in the specification

Grouped by tag, exactly as declared in `obis_v3.yml`.

**Occurrence**

| Path | Purpose |
| --- | --- |
| `GET /occurrence` | Find occurrence records. The main data endpoint. |
| `GET /occurrence/{id}` | Fetch a single occurrence record by OBIS record UUID. |
| `GET /occurrence/grid/{precision}` | Gridded occurrences as GeoJSON. Capped at 100,000 features. |
| `GET /occurrence/grid/{precision}/kml` | Same, as KML. Capped at 100,000 features. |
| `GET /occurrence/points` | Point occurrences as GeoJSON, aggregated to Geohash precision 8. Capped at 100,000 features. |
| `GET /occurrence/point/{x}/{y}` | Point occurrences at a location, Geohash precision 8. |
| `GET /occurrence/point/{x}/{y}/{z}` | Point occurrences at a location, precision from zoom level. |
| `GET /occurrence/tile/{x}/{y}/{z}` | Point occurrences for a tile as GeoJSON. |
| `GET /occurrence/tile/{x}/{y}/{z}.mvt` | Gridded occurrences for a tile as MVT. |
| `GET /occurrence/centroid` | Centroid of a selection. Returns `{lat, lon}`. |

**Taxon**

| Path | Purpose |
| --- | --- |
| `GET /taxon/{id}` | Taxon record by AphiaID. |
| `GET /taxon/{scientificname}` | Taxon record by scientific name. |
| `GET /taxon/annotations` | WoRMS scientific-name annotations. |

**Checklist**

| Path | Purpose |
| --- | --- |
| `GET /checklist` | Species checklist for a selection. |
| `GET /checklist/redlist` | Checklist restricted to IUCN Red List species. |
| `GET /checklist/newest` | Checklist of most recently added species. |

**Node**, **Dataset**, **Institute**, **Area**, **Country**

| Path | Purpose |
| --- | --- |
| `GET /node/{id}` | Node record by node UUID. |
| `GET /node/{id}/activities` | Node activities. |
| `GET /dataset` | Find dataset records. |
| `GET /dataset/{id}` | Dataset record by dataset UUID. |
| `GET /dataset/{id}/errors` | Dataset loading errors. |
| `GET /institute` | Find institute records. |
| `GET /institute/{id}` | Institute record by OceanExpert ID. |
| `GET /area` | List areas. Takes no parameters. |
| `GET /area/{id}` | Area record by area ID. |
| `GET /country` | List countries. Takes no parameters. |
| `GET /country/{id}` | Country record by country ID. |

**Facet**, **Statistics**, **Metrics**

| Path | Purpose |
| --- | --- |
| `GET /facet` | Record counts per facet value. |
| `GET /statistics` | Record, species, taxon, and dataset counts plus year range. |
| `GET /statistics/years` | Presence records per year. |
| `GET /statistics/env` | Records per SST, SSS, or depth bin. |
| `GET /statistics/qc` | QC summary: missing and invalid fields, on-land, non-marine, no AphiaID. |
| `GET /statistics/composition` | Taxonomic composition overview. |
| `GET /metrics` | Yearly download counts for a dataset or node. |
| `GET /metrics/downloads` | Download counts for a dataset within a date range. `datasetid` is required. |

### 2.2 Divergences between the specification and the live service

These matter because the client must not promise what the service does not do, and should
not withhold what it does.

1. **`GET /node` (list all nodes) is not in the specification but works.** It returns
   `{"total": 39, "results": [...]}` with full node records including feeds and contacts.
   **(observed.)** The spec only declares `/node/{id}` and `/node/{id}/activities`.
   Treat the list form as real but undocumented, and pin it with an integration test.

2. **`GET /taxon` (search taxa) does not exist.** It returns HTTP 404 with an HTML body
   `Cannot GET /taxon`. **(observed.)** The specification contains this path commented out.
   Taxon lookup is by AphiaID or by exact scientific name only.

3. **`id_dataset` is a dangling reference in the specification.** `/dataset/{id}` and
   `/dataset/{id}/errors` both `$ref` `#/components/parameters/id_dataset`, which is never
   defined. The path parameter is a dataset UUID; this is a defect in the spec document,
   not in the service.

4. **`/dataset` accepts `datasetid` although the spec does not list it.** `GET
   /dataset?datasetid=<uuid>` returns `total: 1`. **(observed.)**

5. **`/checklist` accepts `size` although the spec does not list it.** `GET
   /checklist?scientificname=Abra&size=1` returns 1 of 30 results. **(observed.)**

6. **`/statistics` honours every occurrence filter, including those the spec does not list
   for it.** This was verified explicitly because the client's route heuristic depends on
   it: a pre-flight count is only usable if it counts the same records the occurrence
   query would return. Comparing `/occurrence.total` against `/statistics.records` for the
   same filters **(observed)**:

   | Filter added to `scientificname=Abra alba` | `/occurrence` total | `/statistics` records |
   | --- | ---: | ---: |
   | (none) | 75,356 | 75,356 |
   | `instituteid=6223` | 16,132 | 16,132 |
   | `datasetid=8acba7e7-…` | 7,943 | 7,943 |
   | `event=true` | 0 | 0 |
   | `hasextensions=DNADerivedData` | 107 | 107 |
   | `measurementtype=Abundance` | 207 | 207 |
   | `startdepth=10` | 30,999 | 30,999 |

   All seven agree, including `instituteid`, `event`, `hasextensions`, and
   `measurementtype`, none of which the spec lists under `/statistics`. So `/statistics`
   is a sound and cheap pre-flight count for an arbitrary occurrence query.

7. **`/taxon/annotations` has a malformed entry in the spec** (its `responses` block sits
   after a commented-out path). It lists `scientificname` twice, and also `taxonid` and
   `taxonrank`.

### 2.3 The spatial aggregation endpoints

Probed on 2026-10-10.

- **`/occurrence/grid/{precision}`** returns a GeoJSON `FeatureCollection` of square
  `Polygon` cells, each with `properties.n`, the record count. Cells are geohash cells
  (precision 2: 11.25° × 5.625°; precision 3: 1.40625° square). **(observed)**
  - Precision 1–12 work, the range of Elasticsearch's `geohash_grid`. **Precision 0 is
    HTTP 500** and **13 and above an HTTP 200 carrying an `error` field**, both naming the
    parse failure; the client validates the range to say what to pass instead. (A first
    probe read precision 9 as silently empty; it had used a polygon holding no records.)
  - The counts honour the occurrence filters: the sum of `n` equals `/statistics.records`
    for `scientificname` alone, with `startdate`, with `absence=true` and with
    `flags=ON_LAND`.
  - **`dropped` is ignored.** `dropped=include` sums to the default count (75,370, against
    75,466 from `/statistics`), and `dropped=true` returns no cells at all, where
    `/statistics` reports 96 records. The client refuses the keyword on these endpoints.
  - Capped at 100,000 features with no indication of truncation: an unfiltered grid at
    precision 5 returns exactly 100,000.
- **`/occurrence/points`** returns a bare GeoJSON `MultiPoint` with no counts; one point
  per occupied precision-8 geohash. Same filter behaviour, including ignoring `dropped`.
- **`/occurrence/centroid`** returns `{"lat", "lon"}`. **When nothing matches, the body is
  empty** (HTTP 200, zero bytes), which is not valid JSON; the client reads it as `nothing`.
- All three report `NAME_NOT_FOUND` in the usual envelope for an unknown name.
- `geometry` accepts `MULTIPOLYGON`: two halves of a box across the antimeridian
  (170°E–180°, 180°–170°W) sum exactly to the `MULTIPOLYGON` of both.

## 3. Parameters

### 3.1 Naming

The query parameter for a WoRMS identifier is **`taxonid`**, not `aphiaid`. `aphiaid` is
not a query parameter anywhere in the API. `AphiaID` appears only as a *response* field:
`aphiaID` in occurrence records from the API, `AphiaID` in the export field reference, and
`aphiaid` in the GeoParquet `interpreted` struct. The three casings are for three
different surfaces and must not be conflated.

The client should expose a Julia-side keyword that reads naturally (`aphiaid` or
`taxonid`) but it must send `taxonid` on the wire.

### 3.2 Filter parameters

Shared by `/occurrence`, `/checklist`, `/dataset`, `/institute`, `/facet`, `/statistics*`
and the geographic occurrence endpoints, with the per-endpoint variations noted in §2.2.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `scientificname` | string | Scientific name. Empty includes all taxa. |
| `taxonid` | string | Taxon AphiaID. |
| `datasetid` | string | Dataset UUID. |
| `areaid` | string | Area ID. |
| `instituteid` | string | Institute ID (OceanExpert ID). |
| `nodeid` | string | Node UUID. |
| `startdate` / `enddate` | string | `YYYY-MM-DD`. |
| `startdepth` / `enddepth` | integer | Meters. |
| `geometry` | string | WKT **or Geohash**. The spec says both. |
| `redlist` | boolean | IUCN Red List species only. |
| `hab` | boolean | Harmful algal bloom species only. |
| `wrims` | boolean | WRiMS (introduced/invasive) species only. |
| `flags` | string | Comma-separated QC flags that must be set. |
| `exclude` | string | Comma-separated QC flags to exclude. |
| `tags` | string | Comma-separated tag URIs. Matching is OR. |
| `dropped` | string | `include` or `true`. See §3.3. |
| `absence` | string | `include` or `true`. See §3.3. |
| `event` | string | `include` or `true`. Pure event records. |

Occurrence-only parameters:

| Parameter | Type | Meaning |
| --- | --- | --- |
| `size` | integer | Page size. Max 10,000, default 10. See §4. |
| `after` | string | Occurrence UUID to page after. See §4. |
| `fields` | string | Comma-separated field allow-list. See §5.4. |
| `mof` | boolean | Include MeasurementOrFact records. |
| `dna` | boolean | Include DNADerivedData records. |
| `extensions` | string | Extensions to include. |
| `hasextensions` | string | Extensions that must be present. |
| `qcfields` | boolean | Include lists of missing and invalid fields. |
| `measurementtype`, `measurementtypeid`, `measurementvalue`, `measurementvalueid`, `measurementunit`, `measurementunitid` | string | Require a matching measurement on the occurrence. |

Facet-only: `facets` (comma-separated facet names), `composite` (boolean).
Tile-only: `precision`, `cellspertile`, `tiletype`, `margin`.

### 3.3 `absence` and `dropped` are tri-state, not boolean

Both take a *string*, and the two non-default values mean different things:

- omitted — exclude these records (the default),
- `include` — return them alongside normal records,
- `true` — return **only** these records.

This is the difference the API offers over the bulk downloads, so it is worth measuring.
For `scientificname=Abra alba` **(observed via `/statistics`)**:

| Query | records | datasets | year range |
| --- | ---: | ---: | --- |
| default | 75,356 | 216 | 1841–2026 |
| `absence=include` | 93,743 | 216 | 1841–2026 |
| `absence=true` | 18,387 | 14 | 1977–2022 |
| `dropped=include` | 75,452 | 218 | 1841–2026 |
| `dropped=true` | 96 | 9 | 1900–2021 |

For this one species, 18,387 absence records — 24% again the presence count — are
invisible in the default view. A client that cannot reach them cannot answer "was the
species looked for and not found?", which is a different question from "was it not
recorded?".

The manual states this directly: "By default absence and dropped records are not included
in downloads and can be obtained through the API" (access.html).

A three-valued Julia enum maps this cleanly; a `Bool` keyword cannot, and would silently
collapse `include` and `true`.

### 3.4 Flags are uppercase and case-sensitive

This is a silent-wrong-answer trap and the strongest single argument for client-side
validation. **(observed on `/statistics?scientificname=Abra alba`:)**

| Request | records returned |
| --- | ---: |
| `flags=NO_DEPTH` | 29,772 |
| `flags=no_depth` | 0 |
| `flags=ON_LAND` | 4,544 |
| `flags=on_land` | 0 |
| `exclude=ON_LAND` | 70,812 (= 75,356 − 4,544) |
| `exclude=on_land` | 75,356 (filter had no effect) |

Lowercase produces no error. `flags=` silently returns an empty result set, and
`exclude=` silently returns the unfiltered set. Both look like valid answers.

The manual's dataquality chapter displays flags in lowercase, because that is how a
different download surface renders them. The API index stores them uppercase, matching
the QC pipeline's own definitions. The client normalizes case before sending. Unknown
flag names are passed through with a warning rather than rejected, since no complete list
exists to reject them against (§13); OBIS confirmed that approach in October 2026.

### 3.5 Canonical flag list

From the QC pipeline reference (`iobis/obis-qc`), with the drop and absence semantics:

| Flag | Raised when | Drops the record |
| --- | --- | --- |
| `NO_COORD` | Coordinates missing, or out of range | yes |
| `ZERO_COORD` | Latitude and longitude both zero | yes |
| `LON_OUT_OF_RANGE` | Longitude outside −180…180 | yes |
| `LAT_OUT_OF_RANGE` | Latitude outside −90…90 | yes |
| `NO_MATCH` | Name does not match WoRMS unambiguously | yes |
| `NOT_MARINE` | Taxon is exclusively freshwater or terrestrial | yes |
| `NO_ACCEPTED_NAME` | No accepted name in WoRMS | no |
| `MARINE_UNSURE` | Marine status uncertain | no |
| `ON_LAND` | Located on land (OpenStreetMap land polygons) | no |
| `NO_DEPTH` | Depth missing, or min exceeds max | no |
| `MIN_DEPTH_EXCEEDS_MAX` | Depth range inverted or out of −100000…11000 | no |
| `DEPTH_EXCEEDS_BATH` | Depth greater than bathymetric depth | no |
| `DATE_IN_FUTURE` | `eventDate` in the future | no |
| `DATE_BEFORE_MIN` | `eventDate` before year 0 | no |

Records are also marked as **absence** (not flagged) when `occurrenceStatus` is `absent`
or when `individualCount` is 0.

Additional values appear in the `flags` facet that are WoRMS name annotations rather than
QC checks. The live global facet **(observed on `/facet?facets=flags`)** returns:
`NO_DEPTH` (109,157,640), `ON_LAND` (31,886,062), `NO_ACCEPTED_NAME` (4,753,705),
`DEPTH_EXCEEDS_BATH` (4,363,230), `MARINE_UNSURE` (2,897,296), `MIN_DEPTH_EXCEEDS_MAX`
(103,507), `WORMS_ANNOTATION_RESOLVABLE` (85,416), `WORMS_ANNOTATION_RESOLVABLE_LOSS`
(29,441), `DEPTH_OUT_OF_RANGE` (16,667), `SCIENTIFICNAMEID_EXTERNAL` (16,655).

Two consequences. First, the facet is truncated — it returned exactly 10 entries, so it is
not a complete enumeration and must not be used as one. Second, the flag vocabulary is
open: `WORMS_ANNOTATION_*`, `DEPTH_OUT_OF_RANGE`, and `SCIENTIFICNAMEID_EXTERNAL` are all
live but absent from the QC reference table. So the client should validate against a known
list *and* accept unknown uppercase flags with a warning rather than refusing them — a
hard allow-list would break the day OBIS adds a check.

Note that `DEPTH_EXCEEDS_BATH` and `DEPTH_OUT_OF_RANGE` are not necessarily errors: the
manual says a measured depth may legitimately be more accurate than the GEBCO bathymetry
the check is based on.

## 4. Pagination

`/occurrence` uses keyset pagination on the record UUID.

- `size` is the page size. Default **10** when omitted. Maximum **10,000**.
  **(observed.)**
- `after` takes an occurrence UUID and is an **exclusive** lower bound.
- Results are ordered by `id` ascending. **(observed:** first page ids came back sorted;
  page 2 requested with `after=<last id of page 1>` had zero overlap with page 1.**)**
- `total` is the full match count and stays constant across pages. **(observed:** 9 pages
  of 1,000 over a 9,863-record query, `total` reported 9,863 on every page.**)**
- Repeating the same request returns the same page. **(observed.)**
- Exhaustion is signalled by an empty `results` array; there is no cursor field in the
  response and no `next` link.

Two properties follow, and both are worth building on:

- **The cursor is a plain UUID string.** Resuming a paginated pull needs only the query
  plus the last id seen — a few bytes, trivially serializable to disk. A resumable
  iterator does not need any server-side session.
- **Ordering is by UUID, not by relevance or date.** So a partial pull is a
  quasi-random sample of the match set, not a prefix in any meaningful order. The
  documentation should say so, otherwise someone will stop a large pull early and treat
  the result as if it were representative of, say, the earliest records.

Other endpoints do **not** paginate. `/dataset` with no filter returns all 6,910 dataset
records in a single response **(observed)**; `/area` returns 799, `/country` 84,
`/institute` 193, `/node` 39. Sizeable, but bounded — the client should still request
gzip and should not assume these stay small.

## 5. Response shapes

### 5.1 The envelope is not uniform

Most endpoints return `{"total": <int>, "results": [...]}`, but several do not
**(all observed)**:

| Endpoint | Shape |
| --- | --- |
| `/occurrence`, `/dataset`, `/taxon/{id}`, `/checklist`, `/area`, `/country`, `/institute`, `/node` | `{total, results}` |
| `/statistics` | bare object: `{records, species, taxa, datasets, specieslevel, yearrange}` |
| `/statistics/years` | bare **array**: `[{year, records}, …]` |
| `/statistics/qc` | bare object: `{fields, flags, onland}` |
| `/occurrence/centroid` | bare object: `{lat, lon}` |
| `/facet` | `{results: {<facet>: [{key, records}, …]}}` — `results` is an object, not an array, and there is no `total` |
| `/metrics` | `{downloads: [{year, records, downloads}, …]}` |

So response decoding has to be per-endpoint. There is no single generic envelope type.

### 5.2 Occurrence records: the field set is not stable

This is the central problem the typed schema has to solve, so it was measured rather than
assumed. Sampling 2,000 occurrence records across five taxa (*Abra alba*, Delphinidae,
*Zostera marina*, *Calanus*, *Thunnus*) **(observed)**:

- **188 distinct field names** appeared.
- **25 fields were present in every record**: `absence`, `aphiaID`, `basisOfRecord`,
  `bathymetry`, `class`, `classid`, `dataset_id`, `decimalLatitude`, `decimalLongitude`,
  `dropped`, `family`, `familyid`, `flags`, `id`, `kingdom`, `kingdomid`, `marine`,
  `node_id`, `order`, `orderid`, `originalScientificName`, `phylum`, `phylumid`,
  `scientificName`, `shoredistance`.
- Everything else is sparse, some of it extremely so: `verbatimLatitude`,
  `higherGeography`, `collectionID`, `recordedByID` and others appeared in a single record
  out of 2,000.

JSON objects simply omit absent keys. A naive row-per-record conversion therefore produces
a different column set for every query, and even for the same query as OBIS ingests new
data. Requirement 1 exists because of this measurement.

### 5.3 Numeric fields arrive as both integer and float

In the same 2,000-record sample, these fields had mixed JSON types **(observed)**:

| Field | integer | float |
| --- | ---: | ---: |
| `bathymetry` | 1,402 | 598 |
| `coordinateUncertaintyInMeters` | 295 | 125 |
| `decimalLatitude` | 34 | 1,966 |
| `decimalLongitude` | 45 | 1,955 |
| `depth` | 567 | 636 |
| `maximumDepthInMeters` | 886 | 292 |
| `minimumDepthInMeters` | 893 | 287 |
| `sss` | 25 | 1,921 |
| `sst` | 14 | 1,932 |

The service is not inconsistent; JSON has one number type and the encoder drops the
fractional part when it is zero. But a decoder that infers types per value yields
`Union{Int64,Float64}` columns, and `decimalLatitude` in particular is a coordinate that
must be `Float64` unconditionally. Every numeric core field needs explicit coercion.

Other typing observations on the occurrence record:

- `flags` is a **JSON array of strings**, e.g. `["NO_DEPTH"]` — *not* a comma-separated
  string. The comma-separated form the manual describes belongs to the CSV downloads.
  Parsing it as a string would be wrong for this API.
- `node_id` is a **JSON array** of node UUIDs. A record can belong to more than one node.
- `date_start`, `date_mid`, `date_end` are **Unix timestamps in milliseconds** (e.g.
  `1432857600000`), not seconds. `Dates.unix2datetime` expects seconds; dividing by 1000
  is required.
- `date_year` is an integer, but `year`, `month`, and `day` are **strings** (`"2015"`,
  `"5"`, `"29"`) — the verbatim provider values, unpadded.
- `eventDate` is a string, sometimes a single ISO timestamp, and per the QC checks it may
  also be an ISO 8601 interval.
- `modified` is a string in `YYYY-MM-DD HH:MM:SS` form, not ISO 8601 with a `T`.
- `sampleSizeValue` came back as the string `"3.0"` while `sampleSizeUnit` is a string —
  verbatim provider values are not coerced.
- `absence` and `dropped` are booleans on the record.

### 5.4 `fields` narrows the response, and not every field is selectable

`fields` takes a comma-separated allow-list and the response contains only those keys
**(observed)**:

| Request | Keys returned |
| --- | --- |
| `fields=id,scientificName,decimalLatitude` | `decimalLatitude`, `id`, `scientificName` |
| `fields=id,dropped,absence` | `absence`, `dropped`, `id` |
| `fields=id,bogusfield` | `id` — unknown names are dropped silently |
| `fields=id,flags` | `id` — **`flags` cannot be selected** |
| `fields=flags` | `{}` — an object with no keys at all |

Two hazards. Unknown field names are discarded without an error, so a typo yields a
column that is silently missing. And `flags` is not selectable even though it is present
in every unrestricted record, so a `fields` request that expects flags gets none — while
the same query without `fields` returns `flags: ["ON_LAND"]`. If the client exposes
`fields`, it must reject `flags` there with an explanatory message.

### 5.5 Dataset records

`GET /dataset` and `GET /dataset/{id}` return the same 23-field record, and the list form
carries the full metadata for every match. Fields: `id`, `title`, `abstract`, `citation`,
`citation_id`, `intellectualrights`, `url`, `archive`, `core`, `extensions`,
`disable_extensions`, `contacts`, `institutes`, `nodes`, `keywords`, `extent`, `feed`,
`statistics`, `downloads`, `created`, `published`, `updated`, `tags`.

The ones that matter for citation and licensing:

- `citation` — free-text citation string supplied in the dataset metadata.
- `citation_id` — a **DOI URL** (e.g. `https://doi.org/10.17031/frdvov`) when present.
  Non-null for 87 of 216 datasets in one sample **(observed)** — roughly 40%.
- `intellectualrights` — the license, as **free text**. See §6.
- `published` — ISO 8601 with milliseconds and `Z` (`2025-09-17T10:21:41.000Z`). Supplies
  the year for citations whose text lacks one, which is exactly what the manual's citation
  template calls for.
- `statistics` — per-dataset counts including `dropped` and `absence`.
- `contacts` and `institutes` — provider details for the citation's "Data provider
  details" slot.

**Occurrence records carry no license field.** The occurrence record has `dataset_id` and
nothing else about rights. License and citation must be joined from the dataset side.
Fortunately `/dataset` accepts the same filters as `/occurrence`, so the citation table
for a query is **one extra request** with the query's own filters, not one request per
dataset.

### 5.6 Taxon and checklist records

Both return WoRMS-derived records. `/checklist` adds a `records` count to the taxon
fields; `/taxon/{id}` adds `vernacularNames`. Shared fields include `scientificName`,
`scientificNameAuthorship`, `taxonID`, `taxonRank`, `taxonomicStatus`,
`acceptedNameUsage`, `acceptedNameUsageID`, `ncbi_id`, the environment flags
(`is_marine`, `is_brackish`, `is_freshwater`, `is_terrestrial`) and the full rank
hierarchy with paired `<rank>` and `<rank>id` fields.

## 6. Licensing

### 6.1 What the policy requires

OBIS accepts exactly three licenses (policy.html, Sections 3 and 7): **CC0**, **CC BY**,
and **CC BY-NC**, with a stated preference for CC0. Section 7 records what OBIS is granted
permission to do, and that restricted data is expected to be censored or generalized by
the provider before publication rather than restricted at the API.

CC BY-NC is the operative one for a client: a result set containing even one CC BY-NC
dataset cannot be redistributed commercially. That is a fact about the result, and the
user needs it before they act on the data, not after.

### 6.2 The license field is free text, and it varies

`intellectualrights` is a prose sentence, not a code. Across the 216 datasets matching
`scientificname=Abra alba` **(observed)**:

| count | `intellectualrights` |
| ---: | --- |
| 133 | `This work is licensed under a  Creative Commons Attribution (CC-BY) 4.0 License` |
| 33 | `This work is licensed under a  Creative Commons Attribution Non Commercial (CC-BY-NC) 4.0 License` |
| 33 | `To the extent possible under law, the publisher has waived all rights…` (CC0) |
| 10 | `This work is licensed under a  Creative Commons Attribution (CC-BY 4.0) License` |
| 3 | `This work is licensed under a  Creative Commons Attribution Non Commercial (CC-BY-NC 4.0) License` |
| 1 | `This work is licensed under a  Creative Commons Attribution 4.0 International` |
| 1 | `Attribution-ShareAlike (CC BY-SA)` |
| 1 | `Unrestricted` |
| 1 | `Restricted` |

Nine spellings for what is essentially three licenses, in one query — note the doubled
space, the two different placements of "4.0", and the two bare words. Across the whole
corpus the licenses table (§7.2) has **63 distinct license strings**. And `Attribution-
ShareAlike (CC BY-SA)` is not one of the three accepted licenses at all, while
`Unrestricted` and `Restricted` are not licenses in any recognizable sense.

So license handling has to be: parse to a normalized value where possible, keep the raw
string always, and represent "unrecognized" as a real category rather than guessing. A
`licenses()` summary that silently drops the odd ones would be worse than useless, because
`Restricted` is precisely the one a user needs to see.

### 6.3 A normalized license URL exists, but only on the export side

The licenses table published with the full export (`s3://obis-open-data/licenses.tsv`) has
columns `id`, `license`, `license_url`, `citation`. The URL column collapses those 63
strings to **12 distinct values**, and those 12 reduce to three CC families plus empty
**(observed over 5,342 rows)**:

| rows | `license_url` |
| ---: | --- |
| 2,591 | `http://creativecommons.org/licenses/by/4.0/legalcode` |
| 1,800 | `http://creativecommons.org/licenses/by-nc/4.0/legalcode` |
| 669 | `http://creativecommons.org/publicdomain/zero/1.0/legalcode` |
| 216 | *(empty)* |
| 57 | the same three, with `https`, a trailing `.ja`, no `legalcode`, or a second URL appended |

Two things follow. The normalization target is well defined: CC0-1.0, CC-BY-4.0,
CC-BY-NC-4.0, plus unknown. And **216 datasets (4%) have no license URL and 351 (6.6%)
have no citation text** — the unknown category is not a theoretical edge case.

This file is a companion to the export, not a live API surface: it was last modified
2025-04-17 and covers 5,342 datasets while `/statistics` currently reports 6,910. It is
useful as a bulk accelerator on the export route, but the API's `/dataset` response is the
current and authoritative source for a live query.

### 6.4 Citation formats

The policy (Section 4) and citing.html give the same templates. Per dataset:

```
[Dataset citation from metadata] [Data provider details] [Dataset]
(Available: Ocean Biodiversity Information System. Intergovernmental Oceanographic
Commission of UNESCO. obis.org. Accessed: YYYY-MM-DD)
```

For a subset drawn from many datasets, in addition to the individual dataset citations
and respecting each dataset's restrictions:

```
OBIS (YEAR) [Data, e.g. Distribution records of Eledone cirrhosa (Lamarck, 1798)]
[Dataset] (Available: Ocean Biodiversity Information System. Intergovernmental
Oceanographic Commission of UNESCO. www.obis.org. Accessed: YYYY-MM-DD)
```

General citation of the system itself:

```
OBIS (YEAR) Ocean Biodiversity Information System. Intergovernmental Oceanographic
Commission of UNESCO. https://obis.org.
```

Derived information products from OBIS are CC0.

Notes for the implementation:

- The policy says "Any use of OBIS data and/or derived products, including (but not
  limited to) software applications, workflows and papers, should be properly cited."
  Software output is named explicitly.
- `Accessed: YYYY-MM-DD` is required and is a property of the *request*, not of the data.
  Only the client knows it, so the client must record it at request time.
- Where the dataset citation carries no year, the manual says to use the year from the
  dataset publication date — available as `published`.
- Some citation strings contain a literal `yyyy-mm-dd` placeholder from the provider
  (seen in the licenses table), and 6.6% are empty. Both need a fallback built from
  `title`, `institutes`, and `published`.
- `citation_id` supplies a DOI for about 40% of datasets — the `doi` field for BibTeX
  output.

## 7. Access routes and volume

### 7.1 What OBIS says about volume

From obis.org/data/access: the API is "suitable for" *programmatic access to smaller
subsets, checklists, and statistics*, and for large downloads the guidance is explicit —
**"use the OBIS dataset on AWS Open Data. Do not parallelize downloads."** The same page
notes that large downloads through the other surfaces are "very slow and cause unnecessary
load on the OBIS systems".

That sentence is the whole of the network-courtesy requirement, stated by the operator:
serial pagination by default, and a real alternative offered before a large pull begins
rather than after it finishes.

The manual adds that the Swagger interface itself returns only the first 10 results and is
not a download tool — consistent with the observed default `size=10`.

### 7.2 The export route

The full export is GeoParquet on AWS Open Data, documented at `iobis/obis-open-data`:

- `s3://obis-open-data/occurrence/<dataset_uuid>.parquet` — **one file per source
  dataset**, roughly 50 GB in total.
- `s3://obis-open-data/dwca/<dataset_uuid>.zip` — source Darwin Core Archives.
- `s3://obis-open-data/licenses.tsv` — the licenses table from §6.3.

The bucket is also reachable over plain HTTPS with no credentials and no AWS SDK
**(observed:** `HEAD https://obis-open-data.s3.amazonaws.com/licenses.tsv` and
`HEAD https://obis-open-data.s3.amazonaws.com/occurrence/8acba7e7-….parquet` both return
200 with `Accept-Ranges: bytes`**)**. Since files are keyed by dataset UUID, a
dataset-scoped export can be fetched directly by URL. Whole-corpus access is the 50 GB
sync.

The Parquet schema is nested and differs from the API's flat JSON: top-level `_id`,
`dataset_id`, `node_ids`, `source`, `interpreted`, `extensions`, `missing`, `invalid`,
`flags`, `dropped`, `absence`, `geometry` (WKB). Provider-supplied terms live under
`source`, OBIS-interpreted ones under `interpreted`. So export rows need a mapping step to
reach the same canonical schema as API rows — the field names differ in nesting and, for
AphiaID, in casing (`interpreted.aphiaid` vs the API's `aphiaID`).

The full OBIS dataset is itself licensed **CC BY-NC** and cited as:

```
Ocean Biodiversity Information System (OBIS) (25 March 2025) OBIS Occurrence Data.
Intergovernmental Oceanographic Commission of UNESCO.
https://doi.org/10.25607/obis.occurrence.b89117cd.
```

### 7.3 Absence and dropped records ARE in the exports — settled

Two OBIS sources disagreed:

- access.html: "Note the disclaimer that such exports will not include records of
  insufficient quality, or absence records."
- `iobis/obis-open-data`: "absence — Absence flag. Note that by default the OBIS
  webservices do not expose absence records, but they are included in this dataset."

**`obis-open-data` is right and access.html is stale. (Observed, and confirmed by OBIS
in October 2026: the absence records are in the exports deliberately, and
[iobis/manual#127](https://github.com/iobis/manual/issues/127) tracks aligning the manual.)** Six per-dataset export
files were read and their `absence` and `dropped` columns counted, then cross-checked
against `/statistics` for the same dataset:

| dataset | export rows | `absence` | `dropped` | API `absence=:only` | API `dropped=:only` | API default |
| --- | --- | --- | --- | --- | --- | --- |
| `947cd13d…` | 5,280 | 4,422 | 0 | 4,422 | — | 858 |
| `7def03fb…` | 31,768 | 24,281 | 0 | 24,281 | — | 7,487 |
| `ee924936…` | 1,990 | 1,616 | 0 | 1,616 | — | 374 |
| `0c44a7dc…` | 261 | 0 | 26 | — | 26 | 235 |
| `500c9a4a…` | 214 | 0 | 16 | — | 16 | 198 |
| `734b7fc4…` | 219 | 0 | 0 | — | — | — |

Every count matches exactly, and each export total is the API's default count plus its
absence or dropped count — so the export is the union, and its flags mean the same records
the API's tri-state selections return.

Consequences for the client:

1. `export_covers` refuses only `event` selections. There is no `event` boolean anywhere in
   the export schema; the only event information is a top-level `_event_id` carried on each
   occurrence, which identifies an event a record belongs to rather than marking the record
   as an event. So pure event records cannot be selected from a file at all.
2. The route difference that remains is **the date**: the export is a periodic snapshot
   (the files read here carried `Last-Modified: 2025-09-20`) and the API is live.
3. Anything reading an export must filter `absence` and `dropped` explicitly. Assuming they
   are absent silently mixes them into an ordinary count.

### 7.4 Reading an export: Parquet2.jl cannot, DuckDB can

**(Observed, on a 261-row export file.)** The schema has 646 elements and 622 leaf columns,
written by `parquet-cpp-arrow version 20.0.0`, with `geo` and `ARROW:schema` key-value
metadata. Fifteen top-level fields, nine of them groups:

| field | kind | children |
| --- | --- | --- |
| `_id`, `_event_id`, `_occurrence_id`, `dataset_id` | BYTE_ARRAY | — |
| `node_ids`, `missing`, `invalid`, `flags`, `tags` | list | 1 |
| `source` | struct | 188 |
| `interpreted` | struct | 276 |
| `extensions` | struct | 2 |
| `dropped`, `absence` | BOOLEAN | — |
| `geometry` | BYTE_ARRAY (WKB) | — |

`interpreted` is the canonical schema's source and already carries the right types:
`decimalLatitude`/`decimalLongitude`/`depth`/`bathymetry` as DOUBLE, `aphiaid` and
`date_start`/`date_mid`/`date_end`/`date_year` as INT64 — the same millisecond epoch as the
API (`616377600000` on a 1989 record).

- **Parquet2.jl v0.2.35 cannot read these files.** It throws before returning anything, in
  `thriftget(::Nothing, :meta_data, nothing)`: that helper calls `getfield` with no guard,
  and the column-chunk lookup returns `nothing` for every group node. Patching that guard
  in gets the file open, and then it says so itself — `Warning: column "source" is nested
  and not supported by Parquet2.jl` — returning empty `NamedTuple`s for structs. Its name
  index is also wrong for this schema: group children surface as top-level siblings, so
  even the flat `absence`, `dropped` and `geometry` become `KeyError`.
- **DuckDB.jl reads them.** Nested access works in SQL (`interpreted.decimalLatitude`),
  types arrive concrete through Tables.jl, and filters push down into the read, so a 232 MB
  export need not be materialized to answer a narrow question. The `DuckDB_jll` artifact is
  ~52 MiB, which is why it belongs behind a package extension rather than in `[deps]`.

## 8. Error semantics

The service does not fail loudly, which is the single most important thing for the client
to compensate for. **(All observed.)**

| Request | Status | Body |
| --- | --- | --- |
| `scientificname=Notaspecies atallxyz` | **200** | `{"total":0,"results":[],"error":"NAME_NOT_FOUND"}` |
| `geometry=NOTWKT` | **200** | `{"total":0,"results":[]}` — no error field at all |
| `flags=BOGUS_FLAG` | **200** | `{"total":0,"results":[]}` — no error field |
| `bogusparam=1` | **200** | full normal result — unknown params are ignored |
| `size=20000` | 400 | plain text: `Something broke: Size 20000 too large (should be 10000 or lower)` |
| `size=-1` | **500** | `{"total":0,"results":[],"error":"[illegal_argument_exception] [size] parameter cannot be negative, found [-1]"}` |
| `startdate=not-a-date` | **500** | `{"total":0,"results":[],"error":"Invalid date format: not-a-date"}` |
| `/taxon/999999999` | 200 | `{"total":0,"results":[]}` |
| `/nosuchthing` | 404 | HTML, not JSON |

What this implies:

1. **HTTP status is not sufficient.** A 200 can carry `error`, and a 500 can carry a
   well-formed envelope with `total: 0`. The client must inspect the `error` key on every
   response regardless of status, and must never treat a 500-with-envelope as valid data.
2. **A misspelled species name is not an error.** `NAME_NOT_FOUND` in a 200 is the only
   signal, and a user reading `total: 0` would reasonably conclude the species is absent
   from the ocean rather than from their spelling. This must be raised, not returned.
3. **Invalid geometry and unknown flags produce no signal whatsoever** — an empty result
   indistinguishable from a genuine empty result. Only client-side validation catches
   these: WKT must be checked before sending, flags must be checked against §3.5.
4. **Unknown parameters are ignored silently.** A typo in a keyword can never be caught by
   the server, so the client's own keyword set is the only guard.
5. **Error bodies come in three forms** — JSON with `error`, plain text (`Something
   broke: …`), and HTML for 404s. Parsing must be defensive about content type.
6. There is no documented `Retry-After` and no 429 was provoked (deliberately — provoking
   one would be discourteous). Backoff must be self-imposed on 429 and 5xx, with the
   caveat that a 5xx here may carry a *permanent* client-side error such as a malformed
   date, which must not be retried.

## 9. Darwin Core

- OBIS data is Darwin Core (policy.html, Section 3). Metadata is EML.
- The Mapper download contains "all 225 possible DwC fields"; the API returns only fields
  that carry data, which is why the observed field set is sparse (§5.2).
- OBIS adds **68 fields** through its QC pipeline (access.html), enumerated on
  obis.org/data/access: the identifiers `id` and `dataset_id`; parsed and validated
  `decimalLongitude`, `decimalLatitude`, `minimumDepthInMeters`, `maximumDepthInMeters`,
  `coordinateUncertaintyInMeters`; the derived `date_start`, `date_mid`, `date_end`,
  `date_year`; `scientificName` and `originalScientificName`; `flags`, `dropped`,
  `absence`; the xylookup-derived `shoredistance`, `bathymetry`, `sst`, `sss`; the WoRMS
  environment flags `marine`, `brackish`, `freshwater`, `terrestrial`; `taxonRank`,
  `AphiaID`, `redlist_category`; and the full WoRMS rank hierarchy from `superdomain`
  through `subforma`.
- The current Darwin Core vocabulary is machine-readable at
  `https://github.com/tdwg/dwc` (`vocabulary/term_versions.csv`): 1,415 term versions of
  which **362 are currently `recommended`** **(observed)**, organized under Location (46),
  Taxon (40), Occurrence (23), Event (22), and others. This is a larger and moving set
  than OBIS's 225, so the client must treat non-core Darwin Core fields as an open set
  and must not hard-code a fixed list of them.

## 10. Interpretation caveats to carry into the documentation

Quoted from the OBIS data policy disclaimer, verbatim:

> Appropriate caution is necessary in the interpretation of results derived from OBIS.
> Users must recognize that the analysis and interpretation of data require background
> knowledge and expertise about marine biodiversity (including ecosystems and taxonomy).
> Users should be aware of possible errors, including in the use of species names,
> geo-referencing, data handling, and mapping. They should cross check their results for
> possible errors and qualify their interpretation of any results accordingly.

> Unless data are collected through activities funded by IOC/IODE, neither UNESCO, IOC,
> IODE, the OBIS Secretariat, nor its employees or contractors, own the data in OBIS and
> they take no responsibility for the quality of data or products based on OBIS, or its
> use or misuse.

The material for the "counts measure sampling effort" section of the documentation is
already in the data. `/statistics/years` for *Abra alba* returns 127 year entries starting
at 8 records in 1841 **(observed)**, and the global year range is 1103–2026. Record counts
per year track survey programs and digitization campaigns, so a worked example can be
built directly from `/statistics/years` and `/facet?facets=datasetName` on a single
species — no external data required.

`shoredistance` is documented as negative when the observation is inland, which pairs with
`ON_LAND` and is a concrete demonstration of why the flags matter.

## 11. Points that changed the plan

Recorded because they contradict assumptions that would otherwise reach the code.

1. **`aphiaid` is not a query parameter; `taxonid` is.** §3.1.
2. **`flags` in an API response is a JSON array, not a comma-separated string.** §5.3.
3. **Occurrence records carry no license.** License lives on the dataset as free text and
   must be joined via `dataset_id`. §5.5, §6.2.
4. **`absence` and `dropped` are tri-state strings, not booleans.** §3.3.
5. **Flags are uppercase and case-sensitive; lowercase fails silently.** §3.4.
6. **`/taxon` does not exist**, and **`/node` does but is undocumented.** §2.2.
7. **The API rarely reports errors as errors.** A 200 can mean failure; a 500 can carry a
   normal-looking envelope. §8.
8. **Two OBIS sources disagree on whether exports contain absence records.** §7.3.

## 12. Open questions

1. Is `licenses.tsv` regenerated with each export, or is the 2025-04-17 timestamp its
   current state? Determines whether it is usable as anything but a stale accelerator.
   (§6.3)
2. Is there a documented request-rate expectation beyond "do not parallelize"? Worth
   asking so the default pacing can be set to something OBIS is comfortable with rather
   than to a guess.
3. Does `size` behave identically on `/checklist` as on `/occurrence`, and does
   `/checklist` support `after`? Undocumented; only `size` was verified. (§2.2)

## 13. Answered since first writing

- **Polygon winding order is irrelevant.** Both orientations of the same box return
  identical counts, so the client does not need to normalize it. (§3.2)
- **`/statistics` agreement was re-verified end to end.** The integration suite checks four
  filter combinations on every run, so a regression in this assumption surfaces rather than
  silently skewing the route heuristic. (§2.2)
- **The exports do contain absence and dropped records.** Counted in six export files and
  reconciled against `/statistics` dataset by dataset; every count matched, and each
  export's total was the API's default count plus them. access.html is stale on this
  point, and OBIS confirmed in October 2026 that the inclusion is deliberate;
  [iobis/manual#127](https://github.com/iobis/manual/issues/127) aligns the manual. (§7.3)
- **There is no complete published enumeration of quality flags.** Confirmed by OBIS in
  October 2026: the facet endpoint is not an enumeration, and OBIS endorsed passing
  unrecognized flags through with a warning, which is what `normalize_flag` does. A revision
  of the QC system is planned, so `KNOWN_FLAGS` should be expected to drift. (§3.5)
- **Parquet2.jl cannot read an OBIS export; DuckDB can.** Nested struct columns are
  unsupported by Parquet2 and everything the canonical schema needs lives under
  `interpreted`. (§7.4)
- **The export bucket needs no credentials.** Confirmed by fetching `licenses.tsv` and a
  per-dataset Parquet file over plain HTTPS, which is why the export route needs no AWS
  SDK. (§7.2)

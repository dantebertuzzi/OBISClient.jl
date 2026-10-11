# Public API

Everything a caller needs. Functions the package uses internally are in
[Internals](internals.md).

## The module

```@docs
OBISClient
```

## Occurrences

```@docs
OBISClient.occurrence
OBISClient.occurrence_pages
OBISClient.occurrence_by_id
OBISClient.OccurrencePages
OBISClient.cursor
OBISClient.fetched
OBISClient.expected
```

## Maps and bounding boxes

```@docs
OBISClient.occurrence_grid
OBISClient.occurrence_points
OBISClient.occurrence_centroid
OBISClient.bbox
```

## Taxa and checklists

```@docs
OBISClient.taxon
OBISClient.taxon_annotations
OBISClient.checklist
OBISClient.checklist_redlist
OBISClient.checklist_newest
```

## Datasets, nodes, institutes, areas, countries

```@docs
OBISClient.dataset
OBISClient.dataset_by_id
OBISClient.dataset_errors
OBISClient.node
OBISClient.node_activities
OBISClient.institute
OBISClient.institute_by_id
OBISClient.area
OBISClient.country
OBISClient.metrics
OBISClient.metrics_downloads
```

## Statistics and facets

```@docs
OBISClient.statistics
OBISClient.statistics_years
OBISClient.statistics_env
OBISClient.statistics_qc
OBISClient.statistics_composition
OBISClient.facet
OBISClient.estimate_size
```

## Results

```@docs
OBISClient.OBISTable
OBISClient.QueryMeta
OBISClient.metadata
OBISClient.nrow
OBISClient.ncol
OBISClient.extra_names
OBISClient.extra_column
```

## Licensing and citation

```@docs
OBISClient.licenses
OBISClient.citations
OBISClient.obis_citation
OBISClient.normalize_license
OBISClient.license_url
OBISClient.permits_redistribution
OBISClient.permits_commercial_use
OBISClient.requires_attribution
OBISClient.ACCEPTED_LICENSES
OBISClient.LICENSE_URLS
```

## Quality flags

```@docs
OBISClient.KNOWN_FLAGS
OBISClient.DROPPING_FLAGS
OBISClient.normalize_flag
OBISClient.normalize_flags
OBISClient.drops_record
```

## The bulk export

```@docs
OBISClient.export_covers
OBISClient.export_url
OBISClient.export_archive_url
OBISClient.download_export
OBISClient.download_exports
OBISClient.export_licenses
OBISClient.read_export
```

## Configuration and caching

```@docs
OBISClient.config
OBISClient.configure!
OBISClient.ClientConfig
OBISClient.QueryCache
OBISClient.cache_entries
OBISClient.revalidate_cache
OBISClient.clear_cache!
OBISClient.default_cache_dir
OBISClient.package_version
```

## Errors

```@docs
OBISClient.OBISError
OBISClient.OBISValidationError
OBISClient.OBISNameNotFoundError
OBISClient.OBISAPIError
OBISClient.OBISConnectionError
OBISClient.OBISLargeQueryError
```

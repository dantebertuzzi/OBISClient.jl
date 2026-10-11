# Internals

These are not part of the public interface and may change without a breaking release. They
are documented because the manual refers to them when explaining how the schema and the
request layer behave.

## Reference material

```@docs
OBISClient.disclaimer
OBISClient.OBIS_DISCLAIMER
OBISClient.RECORD_SELECTIONS
```

## The schema

The canonical schema is what makes a result's columns the same for every query against an
endpoint. Each entry declares a column name, a concrete element type, and how the raw JSON
value is converted.

```@docs
OBISClient.FieldSpec
OBISClient.OCCURRENCE_SCHEMA
OBISClient.TAXON_SCHEMA
OBISClient.DATASET_SCHEMA
OBISClient.NODE_SCHEMA
OBISClient.INSTITUTE_SCHEMA
OBISClient.AREA_SCHEMA
OBISClient.COUNTRY_SCHEMA
OBISClient.coerce_field
OBISClient.coerce_scalar
OBISClient.coerce_strlist
OBISClient.coerce_named_list
OBISClient.column_type
OBISClient.schema_names
OBISClient.coerce_epoch_ms
OBISClient.coerce_iso_datetime
OBISClient.coerce_flagset
OBISClient.build_table
OBISClient.json_to_julia
OBISClient.empty_table
OBISClient.take_rows
OBISClient.concat_tables
```

## Request layer

```@docs
OBISClient.api_get
OBISClient.raw_request
OBISClient.build_url
OBISClient.request_headers
OBISClient.retryable
OBISClient.backoff_delay
OBISClient.throttle!
OBISClient.check_response
OBISClient.results_of
OBISClient.total_of
OBISClient.TRANSPORT
OBISClient.default_transport
OBISClient.DOWNLOADER
OBISClient.default_downloader
OBISClient.http_error_advice
OBISClient.MAX_URL_LENGTH
OBISClient.check_url_length
OBISClient.LAST_REQUEST
```

## Parameter handling

```@docs
OBISClient.build_params
OBISClient.QueryParams
OBISClient.selection_value
OBISClient.validate_geometry
OBISClient.geometry_wkt
OBISClient.geointerface_wkt
OBISClient.spatial_params
OBISClient.format_date
OBISClient.validate_depth
OBISClient.validate_uuid
OBISClient.validate_size
OBISClient.validate_fields
OBISClient.sorted_pairs
```

## Rights and citation

```@docs
OBISClient.CitationEntry
OBISClient.citation_entries
OBISClient.format_citation
OBISClient.bibtex_escape
OBISClient.dataset_counts
OBISClient.dataset_info
OBISClient.dataset_filters
OBISClient.attach_licenses
OBISClient.finalize_dataset_table
OBISClient.fetch_dataset_records
OBISClient.DatasetInfo
```

## Access routes

```@docs
OBISClient.guard_query_size
OBISClient.stats_filters
OBISClient.parse_licenses_tsv
OBISClient.raw_request_absolute
OBISClient.download_file
OBISClient.EXPORT_COLUMN_SOURCES
OBISClient.export_select
```

## Cache

```@docs
OBISClient.cache_key
OBISClient.cached_body
OBISClient.store_body!
```

## Constants and helpers

```@docs
OBISClient.DEFAULT_BASE_URL
OBISClient.DEFAULT_EXPORT_URL
OBISClient.REPO_URL
OBISClient.MAX_PAGE_SIZE
OBISClient.GRID_FEATURE_CAP
OBISClient.GRID_PRECISIONS
OBISClient.format_count
```

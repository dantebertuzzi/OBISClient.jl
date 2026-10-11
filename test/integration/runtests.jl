# Integration tests against the live OBIS API.
#
# These are not part of the default suite and never run in CI on every push. Their purpose
# is to detect changes in the API that the recorded fixtures would hide: a renamed field, a
# changed page-size limit, an error that stops being reported the way it was.
#
# Run them deliberately:
#
#     julia --project=. test/integration/runtests.jl
#
# They are written to be gentle: a handful of small, serial requests with the package's own
# courtesy pacing in force.

using Test
using Dates
using Tables
using OBISClient

# The export reader lives in a package extension, so it is exercised only when DuckDB is
# available. Running this file the documented way skips that testset; the scheduled job
# runs it in a temporary environment that has DuckDB, because export schema drift is
# exactly the kind of change recorded fixtures would hide.
const HAS_DUCKDB = try
    @eval using DuckDB
    true
catch
    false
end

OBISClient.configure!(; request_gap=0.5, page_size=5)

@testset "OBIS live API" begin
    @testset "the envelope and field names are unchanged" begin
        recs = OBISClient.occurrence("Abra alba"; limit=5, licenses=false, check_size=false)
        @test OBISClient.nrow(recs) == 5

        # Fields the package treats as always present. If one of these disappears, the
        # schema needs revisiting rather than silently filling with `missing`.
        for name in
            (:id, :dataset_id, :scientificName, :decimalLatitude, :decimalLongitude,
            :flags, :dropped, :absence, :aphiaID)
            @test haskey(recs, name)
            @test !all(ismissing, Tables.getcolumn(recs, name))
        end

        @test all(x -> x isa Float64, skipmissing(recs.decimalLatitude))
        @test all(x -> x isa Float64, skipmissing(recs.decimalLongitude))
    end

    @testset "timestamps are still milliseconds" begin
        recs = OBISClient.occurrence(
            "Abra alba"; limit=20, licenses=false, check_size=false
        )
        dates = collect(skipmissing(recs.date_start))
        if !isempty(dates)
            # If the API ever switched to seconds, these would land near 1970.
            @test all(d -> Date(1700) < Date(d) < Date(2100), dates)
        end
    end

    @testset "flags are still upper case and case-sensitive" begin
        # This is the behaviour the package normalizes around; if it changed, the
        # normalization would become unnecessary rather than wrong, but we want to know.
        upper = OBISClient.statistics("Abra alba"; flags="ON_LAND")["records"]
        @test upper > 0

        params = OBISClient.QueryParams()
        params["scientificname"] = "Abra alba"
        params["flags"] = "on_land"
        lower = OBISClient.api_get("statistics", params)
        @test Int(lower[:records]) == 0
    end

    @testset "absence and dropped are still API-only and non-empty" begin
        base = OBISClient.statistics("Abra alba")["records"]
        absence = OBISClient.statistics("Abra alba"; absence=:only)["records"]
        included = OBISClient.statistics("Abra alba"; absence=:include)["records"]

        @test absence > 0
        @test included == base + absence

        dropped = OBISClient.statistics("Abra alba"; dropped=:only)["records"]
        @test dropped > 0
    end

    @testset "pagination is still keyset on id" begin
        pages = OBISClient.occurrence_pages("Abra alba"; page_size=5)
        p1, st = iterate(pages)
        p2, _ = iterate(pages, st)
        @test issorted(p1.id)
        @test isempty(intersect(Set(p1.id), Set(p2.id)))
        @test all(id -> id > p1.id[end], p2.id)
    end

    @testset "the page size limit is still 10,000" begin
        params = OBISClient.QueryParams()
        params["scientificname"] = "Abra alba"
        params["size"] = "10000"
        params["fields"] = "id"
        payload = OBISClient.api_get("occurrence", params)
        @test length(OBISClient.results_of(payload)) == 10_000
    end

    @testset "an unmatched name still reports NAME_NOT_FOUND in a 200" begin
        @test_throws OBISClient.OBISNameNotFoundError OBISClient.occurrence(
            "Notaspecies atallxyz"; limit=1, check_size=false
        )
    end

    @testset "flags cannot be selected through fields" begin
        # The package rejects this locally; here we confirm the API behaviour it is
        # protecting against has not changed.
        params = OBISClient.QueryParams()
        params["scientificname"] = "Abra alba"
        params["size"] = "1"
        params["fields"] = "id,flags"
        rec = first(OBISClient.results_of(OBISClient.api_get("occurrence", params)))
        @test !haskey(rec, :flags)
    end

    @testset "dataset rights are still free text under intellectualrights" begin
        ds = OBISClient.dataset_by_id("8acba7e7-2e50-4490-8328-b78a30472508")
        @test OBISClient.nrow(ds) == 1
        @test !ismissing(ds.intellectualrights[1])
        @test ds.license[1] in OBISClient.ACCEPTED_LICENSES
        @test !ismissing(ds.citation[1])
    end

    @testset "statistics still honours every occurrence filter" begin
        # The route heuristic depends on this: a pre-flight count is only useful if it
        # counts the records the occurrence query would return.
        for kwargs in (
            (; scientificname="Abra alba"),
            (; scientificname="Abra alba", instituteid=6223),
            (; scientificname="Abra alba", startdepth=10),
            (; scientificname="Abra alba", hasextensions="DNADerivedData"),
        )
            est = OBISClient.estimate_size(; kwargs...)
            params = OBISClient.build_params(; kwargs..., size=1)
            actual = OBISClient.total_of(OBISClient.api_get("occurrence", params))
            @test est == actual
        end
    end

    @testset "the spatial endpoints still behave as NOTES.md 2.3 records" begin
        # The grid counts the records statistics counts, under the filters it honours.
        for kwargs in (
            (; scientificname="Abra alba"),
            (; scientificname="Abra alba", startdate=Date(2000, 1, 1)),
            (; scientificname="Abra alba", absence=:only),
        )
            g = OBISClient.occurrence_grid(; precision=2, kwargs...)
            @test sum(g.records) == OBISClient.statistics(; kwargs...)["records"]
        end

        # `dropped` is still ignored. If this starts failing, OBIS has fixed it and the
        # refusal in `spatial_params` can go.
        params = OBISClient.build_params(; scientificname="Abra alba", dropped=:only)
        payload = OBISClient.api_get("occurrence/grid/2", params)
        @test isempty(payload[:features])
        @test OBISClient.statistics("Abra alba"; dropped=:only)["records"] > 0

        # Precision 12 is still the finest the grid serves; 13 is still an error.
        params = OBISClient.build_params(; scientificname="Abra alba")
        @test !isempty(OBISClient.api_get("occurrence/grid/12", params)[:features])
        @test_throws OBISClient.OBISAPIError OBISClient.api_get(
            "occurrence/grid/13", params
        )

        c = OBISClient.occurrence_centroid("Abra alba")
        @test c !== nothing
        @test OBISClient.occurrence_centroid("Abra alba"; startdate=Date(2100, 1, 1)) ===
            nothing
    end

    @testset "undocumented endpoints that the package relies on" begin
        # `/node` as a list is not in the API specification but is used by `OBISClient.node()`.
        nodes = OBISClient.node()
        @test OBISClient.nrow(nodes) > 10

        # `/dataset?datasetid=` is likewise undocumented and used by the rights lookup.
        ds = OBISClient.dataset(; datasetid="8acba7e7-2e50-4490-8328-b78a30472508")
        @test OBISClient.nrow(ds) == 1
    end

    @testset "the export bucket is reachable without credentials" begin
        licenses = OBISClient.export_licenses()
        @test OBISClient.nrow(licenses) > 1000
        @test "CC-BY-NC-4.0" in Set(licenses.license)
    end

    if !HAS_DUCKDB
        @info "DuckDB not available; skipping the export reader against a live file."
    else
        @testset "an export still reads into the canonical schema" begin
            # The reader depends on the shape of the published files: the pipeline's values
            # under `interpreted`, the AphiaID spelled `aphiaid` there, `absence` and
            # `dropped` as top-level booleans. A change to any of that would break the bulk
            # route silently, and nothing in the offline suite would notice.
            #
            # A small dataset on purpose — 220 kB against the 232 MB of a large one.
            id = "0c44a7dc-7f06-4eab-b831-4cae103c9902"
            mktempdir() do dir
                path = OBISClient.download_export(id; dir=dir)
                table = OBISClient.read_export(path; licenses=false)

                reference = OBISClient.occurrence(; datasetid=id, licenses=false,
                    limit=nothing,
                    check_size=false)
                @test Tables.columnnames(table) == Tables.columnnames(reference)
                @test OBISClient.nrow(table) == OBISClient.nrow(reference)
                @test Set(table.id) == Set(reference.id)

                # `:exclude` is the default on both routes, so the counts have to agree.
                dropped = OBISClient.read_export(path; dropped=:only, licenses=false)
                @test OBISClient.nrow(dropped) ==
                    OBISClient.statistics(; datasetid=id, dropped=:only)["records"]

                @test all(x -> x isa Float64, skipmissing(table.decimalLatitude))
                @test all(f -> f isa Set{String}, table.flags)
                @test all(x -> x isa Int, skipmissing(table.aphiaID))
            end
        end
    end
end

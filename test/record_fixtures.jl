# Record API responses for the offline test suite.
#
# Run this by hand when the fixtures need refreshing, never from CI:
#
#     julia --project=test test/record_fixtures.jl
#
# It reaches the live API. Responses are written to test/fixtures/ and indexed by request
# URL in manifest.json, which the mock transport in mock.jl reads back. Requests are kept
# small and serial, in keeping with the courtesy rules the package itself follows.

using HTTP
using JSON3

const FIXTURE_DIR = joinpath(@__DIR__, "fixtures")
const BASE = "https://api.obis.org/v3/"
const EXPORT_BASE = "https://obis-open-data.s3.amazonaws.com/"
const UA = "OBISClient.jl fixture recorder (https://github.com/dantebertuzzi/OBISClient.jl)"

# name => path, so a test can refer to a fixture by an obvious name.
const REQUESTS = [
    "occurrence_page1" => "occurrence?scientificname=Abra%20alba&size=3",
    "occurrence_page2" => "occurrence?scientificname=Abra%20alba&size=3&after=PLACEHOLDER",
    "occurrence_absence_only" => "occurrence?scientificname=Abra%20alba&absence=true&size=3",
    "occurrence_dropped_only" => "occurrence?scientificname=Abra%20alba&dropped=true&size=3",
    "occurrence_on_land" => "occurrence?scientificname=Abra%20alba&flags=ON_LAND&size=3",
    "occurrence_diverse" => "occurrence?scientificname=Delphinidae&size=25",
    "occurrence_empty" => "occurrence?scientificname=Abra%20alba&geometry=POLYGON%20((0%200,%200%200.001,%200.001%200.001,%200.001%200,%200%200))&size=3",
    "occurrence_name_not_found" => "occurrence?scientificname=Notaspecies%20atallxyz&size=3",
    "occurrence_single" => "occurrence/0001837f-afc5-45a9-a76d-b63ab73fb93c",
    "dataset_single" => "dataset/8acba7e7-2e50-4490-8328-b78a30472508",
    "occurrence_grid" => "occurrence/grid/2?scientificname=Abra%20alba",
    # Absences only: the full point set for Abra alba is close to a megabyte.
    "occurrence_points" => "occurrence/points?scientificname=Abra%20alba&absence=true",
    "occurrence_centroid" => "occurrence/centroid?scientificname=Abra%20alba",
    # No record matches, which the endpoint answers with an empty body.
    "occurrence_centroid_empty" => "occurrence/centroid?scientificname=Abra%20alba&startdate=2030-01-01",
    "statistics_abra" => "statistics?scientificname=Abra%20alba",
    "statistics_abra_absence" => "statistics?scientificname=Abra%20alba&absence=true",
    "statistics_mollusca" => "statistics?scientificname=Mollusca",
    "statistics_years" => "statistics/years?scientificname=Abra%20alba",
    "statistics_qc" => "statistics/qc?scientificname=Abra%20alba",
    "facet_flags" => "facet?facets=flags&scientificname=Abra%20alba",
    "taxon_by_id" => "taxon/141433",
    "taxon_by_name" => "taxon/Abra%20alba",
    "checklist" => "checklist?scientificname=Abra&size=5",
    "node_list" => "node",
    "area_list" => "area",
    "country_list" => "country",
    "institute_list" => "institute?scientificname=Abra%20alba",
    "size_too_large" => "occurrence?scientificname=Abra%20alba&size=20000",
    "metrics_dataset" => "metrics?datasetid=8acba7e7-2e50-4490-8328-b78a30472508",
    "metrics_downloads" => "metrics/downloads?datasetid=8acba7e7-2e50-4490-8328-b78a30472508",
    # A narrow window: unbounded, the by-time response is four megabytes of individual
    # download events, which is not a fixture.
    "metrics_downloads_by_time" => "metrics/downloads?datasetid=8acba7e7-2e50-4490-8328-b78a30472508&startdate=2018-10-01&enddate=2018-12-01&groupby=time",
]

function fetch(url)
    r = HTTP.get(
        url;
        headers=["User-Agent" => UA, "Accept" => "application/json"],
        status_exception=false,
        redirect=true,
    )
    sleep(0.4)   # stay well clear of any rate limit while recording
    return r.status, String(r.body)
end

function main()
    mkpath(FIXTURE_DIR)
    manifest = Dict{String,Any}()

    # The second page needs a cursor from the first, so page 1 is fetched first and its
    # last id substituted into page 2's URL.
    cursor = nothing

    for (name, path) in REQUESTS
        url = BASE * path
        if occursin("PLACEHOLDER", path)
            cursor === nothing && error("page 1 must be recorded before page 2")
            url = BASE * replace(path, "PLACEHOLDER" => cursor)
        end

        status, body = fetch(url)
        println(rpad(name, 30), status, "  ", length(body), " bytes")

        file =
            name * (
                if startswith(strip(body), "{") || startswith(strip(body), "[")
                    ".json"
                else
                    ".txt"
                end
            )
        write(joinpath(FIXTURE_DIR, file), body)
        manifest[url] = Dict("status" => status, "file" => file, "name" => name)

        if name == "occurrence_page1"
            payload = JSON3.read(body)
            cursor = String(last(payload.results).id)
        end
    end

    # A trimmed dataset list: the full response for this query is several megabytes, and
    # the tests only need enough datasets to cover the recorded occurrences and to show a
    # mix of licences.
    ds_url = BASE * "dataset?scientificname=Abra%20alba"
    status, body = fetch(ds_url)
    payload = JSON3.read(body)
    wanted = Set{String}()
    for name in ("occurrence_page1", "occurrence_page2", "occurrence_absence_only",
        "occurrence_dropped_only", "occurrence_on_land", "occurrence_diverse")
        f = joinpath(FIXTURE_DIR, name * ".json")
        isfile(f) || continue
        p = JSON3.read(read(f, String))
        haskey(p, :results) || continue
        for r in p.results
            haskey(r, :dataset_id) && push!(wanted, String(r.dataset_id))
        end
    end
    kept = Any[]
    seen_licenses = Set{String}()
    for r in payload.results
        id = String(r.id)
        rights = get(r, :intellectualrights, "")
        rights_s = rights === nothing ? "" : String(rights)
        if id in wanted || !(rights_s in seen_licenses)
            push!(kept, r)
            push!(seen_licenses, rights_s)
        end
        length(kept) >= 20 && id ∉ wanted && break
    end
    trimmed = Dict("total" => length(kept), "results" => kept)
    write(joinpath(FIXTURE_DIR, "dataset_list.json"), JSON3.write(trimmed))
    manifest[ds_url] = Dict(
        "status" => status, "file" => "dataset_list.json", "name" => "dataset_list"
    )
    println(rpad("dataset_list", 30), status, "  trimmed to ", length(kept), " datasets")

    # A slice of the export licence table, enough to exercise the TSV parser, plus the rows
    # for the datasets the export fixtures come from — the licence join in `read_export` is
    # only testable if those two are in the table.
    lic_url = EXPORT_BASE * "licenses.tsv"
    r = HTTP.get(lic_url; headers=["User-Agent" => UA], status_exception=false)
    whole = String(r.body)
    # Roughly the first 60 kB, cut at a row boundary. `thisind` because the table is UTF-8
    # and an arbitrary byte offset can land inside a character.
    cut = thisind(whole, min(60_000, ncodeunits(whole)))
    text = whole[1:something(findprev('\n', whole, cut), cut)]
    for (_, dataset, _) in EXPORT_FIXTURES
        occursin(dataset, text) && continue
        i = findfirst(dataset, whole)
        i === nothing && continue
        stop = findnext('\n', whole, last(i))
        text *= whole[first(i):(stop === nothing ? lastindex(whole) : stop)]
    end
    write(joinpath(FIXTURE_DIR, "licenses.tsv"), text)
    manifest[lic_url] = Dict(
        "status" => 200, "file" => "licenses.tsv", "name" => "export_licenses"
    )
    println(rpad("export_licenses", 30), "200  ", length(text), " bytes")

    open(joinpath(FIXTURE_DIR, "manifest.json"), "w") do io
        JSON3.pretty(io, manifest)
    end
    println("\nWrote ", length(manifest), " fixtures to ", FIXTURE_DIR)

    record_export_fixtures()
    return nothing
end

# Two slices of real per-dataset exports, for the DuckDB extension.
#
# Cut from the files themselves rather than written by hand: the point of the reader is that
# it copes with the export's actual shape — 622 columns, the provider's terms nested under
# `source` and the pipeline's under `interpreted` — and a fixture that flattened any of that
# would test nothing. Five rows each is enough, and the schema is most of the file size.
#
# The two datasets are chosen for what they contain: one has records the pipeline dropped,
# the other has absence records, and neither has both.
const EXPORT_FIXTURES = [
    ("export_dropped.parquet", "0c44a7dc-7f06-4eab-b831-4cae103c9902", "dropped"),
    ("export_absence.parquet", "947cd13d-3f49-4b8f-9f82-0fc3aadb1b85", "absence"),
]

function record_export_fixtures()
    DuckDB = Base.require(
        Base.PkgId(
            Base.UUID("d2f5444f-75bc-4fdf-ac35-56f514c445e1"), "DuckDB"
        ),
    )
    db = DuckDB.DBInterface.connect(DuckDB.DB)

    mktempdir() do dir
        for (file, dataset, flag) in EXPORT_FIXTURES
            url = EXPORT_BASE * "occurrence/" * dataset * ".parquet"
            whole = joinpath(dir, dataset * ".parquet")
            r = HTTP.get(url; headers=["User-Agent" => UA], status_exception=false)
            write(whole, r.body)

            out = joinpath(FIXTURE_DIR, file)
            DuckDB.DBInterface.execute(
                db,
                """
                COPY (
                    (SELECT * FROM '$(whole)' WHERE $(flag) IS NOT TRUE LIMIT 2)
                    UNION ALL
                    (SELECT * FROM '$(whole)' WHERE $(flag) IS TRUE LIMIT 3)
                ) TO '$(out)' (FORMAT PARQUET, COMPRESSION ZSTD)
                """,
            )
            println(rpad(file, 30), filesize(out), " bytes  (5 rows, mixed $(flag))")
        end
    end
    return nothing
end

main()

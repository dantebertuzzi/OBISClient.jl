@testset "cache stores and replays responses" begin
    mktempdir() do dir
        cache = OBISClient.QueryCache(dir)
        old = OBISClient.config().cache
        try
            OBISClient.configure!(; cache=cache)
            with_mock() do
                first = OBISClient.occurrence("Abra alba"; limit=3)
                n_requests = length(REQUEST_LOG)
                @test n_requests >= 1

                # A repeat of the same query is served from disk.
                empty!(REQUEST_LOG)
                second = OBISClient.occurrence("Abra alba"; limit=3)
                @test isempty(REQUEST_LOG)
                @test second.id == first.id
                @test second.decimalLatitude == first.decimalLatitude
            end
        finally
            OBISClient.configure!(; cache=old)
        end
    end
end

@testset "cache entries record provenance" begin
    mktempdir() do dir
        cache = OBISClient.QueryCache(dir)
        old = OBISClient.config().cache
        try
            OBISClient.configure!(; cache=cache)
            with_mock() do
                OBISClient.occurrence("Abra alba"; limit=3, licenses=false)
            end

            entries = OBISClient.cache_entries(cache)
            @test !isempty(entries)
            e = first(entries)
            @test haskey(e, "endpoint")
            @test haskey(e, "retrieved")
            @test haskey(e, "parameters")
            @test e["package_version"] == string(OBISClient.package_version())
            @test e["bytes"] > 0

            # What is stored is the raw response, not the parsed table, so a re-run
            # reproduces the original data even if the package's parsing has changed.
            key = e["key"]
            body = read(joinpath(dir, key * ".json"), String)
            @test occursin("\"results\"", body)

            @test OBISClient.clear_cache!(cache) == length(entries)
            @test isempty(OBISClient.cache_entries(cache))
        finally
            OBISClient.configure!(; cache=old)
        end
    end
end

@testset "a read-only cache refuses to reach the network" begin
    mktempdir() do dir
        old = OBISClient.config().cache
        try
            OBISClient.configure!(; cache=OBISClient.QueryCache(dir))
            with_mock() do
                OBISClient.occurrence("Abra alba"; limit=3, licenses=false)
            end

            # Reproducing an analysis must fail loudly if the data is not the data that was
            # cached, rather than quietly fetching today's version.
            OBISClient.configure!(; cache=OBISClient.QueryCache(dir; readonly=true))
            with_mock() do
                replayed = OBISClient.occurrence("Abra alba"; limit=3, licenses=false)
                @test OBISClient.nrow(replayed) == 3
                @test isempty(REQUEST_LOG)

                @test_throws OBISClient.OBISAPIError OBISClient.occurrence(
                    "Abra alba"; absence=:only, limit=3, licenses=false, check_size=false
                )
            end
        finally
            OBISClient.configure!(; cache=old)
        end
    end
end

@testset "cache keys separate different queries" begin
    mktempdir() do dir
        cache = OBISClient.QueryCache(dir)
        a = OBISClient.build_params(; scientificname="Abra alba")
        b = OBISClient.build_params(; scientificname="Abra alba", absence=:only)
        @test OBISClient.cache_key("occurrence", a; base_url="https://api.obis.org/v3/") !=
            OBISClient.cache_key("occurrence", b; base_url="https://api.obis.org/v3/")
        # The endpoint is part of the key, so two endpoints with identical filters do not
        # collide.
        @test OBISClient.cache_key("occurrence", a; base_url="https://api.obis.org/v3/") !=
            OBISClient.cache_key("checklist", a; base_url="https://api.obis.org/v3/")
    end
end

@testset "an unreadable cache entry is skipped, not fatal" begin
    mktempdir() do dir
        cache = OBISClient.QueryCache(dir)
        # A truncated write — an interrupted process, a full disk — must not make the whole
        # cache unlistable, which would leave the user with no way to see or clear it.
        write(joinpath(dir, "broken.meta.json"), "{ not json")
        @test OBISClient.cache_entries(cache) == Dict{String,Any}[]
    end
end

# A server whose data can be changed between requests: it answers `If-None-Match` with a
# 304 while the body is the one the tag was computed from, as OBIS does.
function revalidation_transport(bodies::Dict{String,String}, sent::Vector)
    return function (url, headers, timeout)
        body = bodies[split(url, '?')[1]]
        etag = string("W/\"", hash(body), "\"")
        inm = [v for (k, v) in headers if k == "If-None-Match"]
        push!(sent, isempty(inm) ? nothing : only(inm))
        !isempty(inm) && only(inm) == etag && return (304, Dict("etag" => etag), "")
        return (200, Dict("etag" => etag), body)
    end
end

@testset "revalidation reports what changed, and keeps the old data" begin
    base = OBISClient.config().base_url
    bodies = Dict(
        base * "statistics" => """{"records":10}""",
        base * "statistics/years" => """[{"year":2000,"records":10}]""",
    )
    sent = Any[]
    mktempdir() do dir
        cache = OBISClient.QueryCache(dir)
        old_cache = OBISClient.config().cache
        old_transport = OBISClient.TRANSPORT[]
        try
            OBISClient.configure!(; cache=cache)
            OBISClient.TRANSPORT[] = revalidation_transport(bodies, sent)
            OBISClient.statistics("Abra alba")
            OBISClient.statistics_years("Abra alba")

            # Nothing changed: every entry is checked with its tag and costs a 304.
            empty!(sent)
            report = OBISClient.revalidate_cache(cache)
            @test length(report) == 2
            @test all(r -> r.status === :unchanged, report)
            @test all(!isnothing, sent)
            @test Tables.istable(report)
            @test only(unique(r.parameters for r in report)) ==
                Dict("scientificname" => "Abra alba")

            # OBIS ingests new records; one endpoint's answer moves.
            bodies[base * "statistics"] = """{"records":11}"""
            report = OBISClient.revalidate_cache(cache)
            status = Dict(r.endpoint => r.status for r in report)
            @test status["statistics"] === :changed
            @test status["statistics/years"] === :unchanged
            # Reporting is all it did: the analysis still sees the data it was built on.
            @test OBISClient.statistics("Abra alba")["records"] == 10

            # Updating is explicit, and then the cache follows the service.
            OBISClient.revalidate_cache(cache; update=true)
            @test OBISClient.statistics("Abra alba")["records"] == 11
            @test all(r -> r.status === :unchanged, OBISClient.revalidate_cache(cache))

            # A read-only cache can be checked but not overwritten.
            ro = OBISClient.QueryCache(dir; readonly=true)
            @test length(OBISClient.revalidate_cache(ro)) == 2
            @test_throws OBISValidationError OBISClient.revalidate_cache(ro; update=true)
        finally
            OBISClient.configure!(; cache=old_cache)
            OBISClient.TRANSPORT[] = old_transport
        end
    end
    @test_throws OBISValidationError OBISClient.revalidate_cache(nothing)
end

@testset "an entry without a tag is compared by its body" begin
    base = OBISClient.config().base_url
    mktempdir() do dir
        cache = OBISClient.QueryCache(dir)
        params = OBISClient.build_params(; scientificname="Abra alba")
        OBISClient.store_body!(cache, "statistics", params, """{"records":10}""", Dict())
        old_transport = OBISClient.TRANSPORT[]
        try
            OBISClient.TRANSPORT[] =
                (url, headers, timeout) -> begin
                    @test !any(k == "If-None-Match" for (k, _) in headers)
                    return (200, Dict{String,String}(), """{"records":10}""")
                end
            @test only(OBISClient.revalidate_cache(cache)).status === :unchanged
        finally
            OBISClient.TRANSPORT[] = old_transport
        end
    end
end

@testset "revalidation skips other services and reports failures" begin
    mktempdir() do dir
        cache = OBISClient.QueryCache(dir)
        params = OBISClient.build_params(; scientificname="Abra alba")
        OBISClient.store_body!(cache, "statistics", params, """{"records":10}""", Dict())
        OBISClient.store_body!(cache, "checklist", params, """{"total":0}""", Dict())

        # An entry fetched from another deployment is not compared against this one.
        stats_key = OBISClient.cache_key(
            "statistics", params; base_url=OBISClient.config().base_url
        )
        meta = joinpath(dir, stats_key * ".meta.json")
        m = copy(JSON3.read(read(meta, String), Dict{String,Any}))
        m["base_url"] = "https://api.example.org/v3/"
        write(meta, JSON3.write(m))

        old_transport = OBISClient.TRANSPORT[]
        try
            # A failure on one entry is reported, and the others are still checked.
            OBISClient.TRANSPORT[] =
                (url, headers, timeout) -> (404, Dict{String,String}(), "not here")
            report = @test_logs (:warn,) OBISClient.revalidate_cache(cache)
            status = Dict(r.endpoint => r.status for r in report)
            @test status["statistics"] === :skipped
            @test status["checklist"] === :failed
        finally
            OBISClient.TRANSPORT[] = old_transport
        end
    end
end

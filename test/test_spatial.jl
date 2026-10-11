@testset "bbox" begin
    @test OBISClient.bbox(2.3, 51.6, 2.6, 51.8) ==
        "POLYGON ((2.3 51.6, 2.6 51.6, 2.6 51.8, 2.3 51.8, 2.3 51.6))"
    # What it builds passes the same check a hand-written geometry does.
    @test OBISClient.validate_geometry(OBISClient.bbox(-10, -5, 10, 5)) isa String

    # Crossing the antimeridian splits the box at 180°, since one polygon cannot span it.
    fiji = OBISClient.bbox(170, -25, -170, -10)
    @test startswith(fiji, "MULTIPOLYGON (((170 -25, 180 -25,")
    @test occursin("((-180 -25, -170 -25, -170 -10, -180 -10, -180 -25))", fiji)
    @test OBISClient.validate_geometry(fiji) == fiji

    @test_throws OBISValidationError OBISClient.bbox(0, 10, 1, 5)       # south above north
    @test_throws OBISValidationError OBISClient.bbox(0, 5, 0, 10)       # no width
    @test_throws OBISValidationError OBISClient.bbox(-181, 0, 1, 1)
    @test_throws OBISValidationError OBISClient.bbox(0, 0, 1, 91)
end

@testset "occurrence_grid" begin
    with_mock() do
        g = OBISClient.occurrence_grid("Abra alba"; precision=2)
        @test collect(Tables.columnnames(g)) ==
            [:west, :south, :east, :north, :longitude, :latitude, :records]
        @test OBISClient.nrow(g) == 30
        @test OBISClient.metadata(g).total == 30
        @test OBISClient.metadata(g).endpoint == "occurrence/grid/2"
        @test eltype(g.records) === Int
        @test sum(g.records) == 75370
        @test all(g.west .< g.longitude .< g.east)
        @test all(g.south .< g.latitude .< g.north)
        # Precision 2 cells are 11.25° by 5.625°.
        @test all(≈(11.25), g.east .- g.west)
        @test all(≈(5.625), g.north .- g.south)
    end

    @test_throws OBISValidationError OBISClient.occurrence_grid("Abra alba"; precision=0)
    @test_throws OBISValidationError OBISClient.occurrence_grid("Abra alba"; precision=9)
    # The endpoint ignores `dropped`, so asking for it is refused before any request.
    @test_throws OBISValidationError OBISClient.occurrence_grid(
        "Abra alba"; precision=2, dropped=:include
    )
    @test_throws OBISValidationError OBISClient.occurrence_grid(
        "Abra alba"; precision=2, dropped=:only
    )
    @test_throws OBISValidationError OBISClient.occurrence_grid(
        "Abra alba"; precision=2, size=10
    )
end

@testset "occurrence_points" begin
    with_mock() do
        p = OBISClient.occurrence_points("Abra alba"; absence=:only)
        @test collect(Tables.columnnames(p)) == [:longitude, :latitude]
        @test OBISClient.nrow(p) == 334
        @test eltype(p.longitude) === Float64
        @test all(-180 .<= p.longitude .<= 180)
        @test all(-90 .<= p.latitude .<= 90)
    end
    @test_throws OBISValidationError OBISClient.occurrence_points(
        "Abra alba"; dropped=:only
    )
end

@testset "occurrence_centroid" begin
    with_mock() do
        c = OBISClient.occurrence_centroid("Abra alba")
        @test c isa NamedTuple{(:longitude, :latitude),Tuple{Float64,Float64}}
        # The southern North Sea, where most Abra alba records are.
        @test 0 < c.longitude < 10
        @test 50 < c.latitude < 58

        # An empty body when nothing matches, which must not read as malformed JSON.
        @test OBISClient.occurrence_centroid("Abra alba"; startdate=Date(2030, 1, 1)) ===
            nothing
    end
end

@testset "an empty body is still an error elsewhere" begin
    old = OBISClient.TRANSPORT[]
    OBISClient.TRANSPORT[] = (url, headers, timeout) -> (200, Dict{String,String}(), "")
    try
        @test_throws OBISClient.OBISAPIError OBISClient.api_get("statistics")
        @test OBISClient.api_get("occurrence/centroid"; allow_empty=true) === nothing
    finally
        OBISClient.TRANSPORT[] = old
    end
end

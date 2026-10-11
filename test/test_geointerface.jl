import GeoInterface as GI

@testset "GeoInterface geometries become WKT" begin
    ring = [(2.0, 51.0), (4.5, 51.0), (4.5, 52.5), (2.0, 52.5), (2.0, 51.0)]
    box = GI.Polygon([ring])

    # The same rectangle as `bbox`, so either can be passed and the cache key agrees.
    @test OBISClient.geometry_wkt(box) == OBISClient.bbox(2.0, 51.0, 4.5, 52.5)
    q = OBISClient.build_params(; geometry=box)
    @test get(q, "geometry", "") == OBISClient.bbox(2.0, 51.0, 4.5, 52.5)

    # A feature stands for its geometry, which is what a shapefile row or a GeoJSON feature is.
    @test OBISClient.geometry_wkt(GI.Feature(box; properties=(name="box",))) ==
        OBISClient.geometry_wkt(box)

    fiji = GI.Polygon([[(170.0, -25.0), (180.0, -25.0), (180.0, -10.0), (170.0, -10.0),
        (170.0, -25.0)]])
    mp = OBISClient.geometry_wkt(GI.MultiPolygon([box, fiji]))
    @test startswith(mp, "MULTIPOLYGON (((2.0 51.0, ")
    @test endswith(
        mp, "(170.0 -25.0, 180.0 -25.0, 180.0 -10.0, 170.0 -10.0, 170.0 -25.0)))"
    )
    @test OBISClient.validate_geometry(mp) == mp

    # A hole is a second ring.
    hole = [(3.0, 51.5), (3.5, 51.5), (3.5, 52.0), (3.0, 52.0), (3.0, 51.5)]
    @test occursin("), (3.0 51.5,", OBISClient.geometry_wkt(GI.Polygon([ring, hole])))

    @test OBISClient.geometry_wkt(GI.Point(1.123456789, 2.0)) == "POINT (1.123457 2.0)"
    @test OBISClient.geometry_wkt(GI.LineString([(0.0, 0.0), (1.0, 1.0)])) ==
        "LINESTRING (0.0 0.0, 1.0 1.0)"
    @test OBISClient.geometry_wkt(GI.MultiPoint([(0.0, 0.0), (1.0, 1.0)])) ==
        "MULTIPOINT ((0.0 0.0), (1.0 1.0))"

    @test OBISClient.geometry_wkt(
        GI.MultiLineString([[(0.0, 0.0), (1.0, 1.0)], [(2.0, 2.0), (3.0, 3.0)]])
    ) == "MULTILINESTRING ((0.0 0.0, 1.0 1.0), (2.0 2.0, 3.0 3.0))"
    @test OBISClient.geometry_wkt(GI.GeometryCollection([GI.Point(1.0, 2.0), box])) ==
        "GEOMETRYCOLLECTION (POINT (1.0 2.0), " * OBISClient.geometry_wkt(box) * ")"

    @test_throws OBISValidationError OBISClient.build_params(; geometry=42)
end

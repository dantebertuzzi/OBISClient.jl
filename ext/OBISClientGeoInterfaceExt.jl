# GeoInterface integration, loaded only when the user already has GeoInterface.
#
# The `geometry` filter is WKT on the wire. Regions of interest rarely start as WKT, though:
# they are shapefiles, GeoJSON, Natural Earth layers. Every package that reads those
# implements GeoInterface, so writing WKT from GeoInterface's traits covers all of them
# without depending on any.

module OBISClientGeoInterfaceExt

using OBISClient
using OBISClient: OBISValidationError
import GeoInterface as GI

"""
    OBISClient.geointerface_wkt(geometry) -> String

WKT for any GeoInterface geometry, or for the geometry of a GeoInterface feature.

Coordinates are rounded to six decimal places, about 0.1 m, which keeps the request short
without moving a boundary by anything a record's own precision could detect. Only the
first two dimensions are written: OBIS filters on longitude and latitude.
"""
function OBISClient.geointerface_wkt(x)
    if GI.isfeature(x)
        g = GI.geometry(x)
        g === nothing && throw(
            OBISValidationError(:geometry, nothing, "The feature has no geometry.")
        )
        return OBISClient.geointerface_wkt(g)
    end
    GI.isgeometry(x) || throw(
        OBISValidationError(
            :geometry,
            typeof(x),
            "Expected WKT, or a geometry or feature from a GeoInterface-compatible " *
            "package (Shapefile.jl, GeoJSON.jl, ArchGDAL, GeometryBasics, …).",
        ),
    )
    io = IOBuffer()
    write_wkt(io, GI.geomtrait(x), x)
    return String(take!(io))
end

coord(v) = string(round(Float64(v); digits=6))
point_text(io, p) = print(io, coord(GI.x(p)), ' ', coord(GI.y(p)))

function points_text(io, line)
    print(io, '(')
    for (i, p) in enumerate(GI.getpoint(line))
        i > 1 && print(io, ", ")
        point_text(io, p)
    end
    return print(io, ')')
end

function children_text(io, geom, f)
    print(io, '(')
    for (i, g) in enumerate(GI.getgeom(geom))
        i > 1 && print(io, ", ")
        f(io, g)
    end
    return print(io, ')')
end

polygon_text(io, poly) = children_text(io, poly, points_text)

function write_wkt(io, ::GI.PointTrait, g)
    return (print(io, "POINT ("); point_text(io, g); print(io, ')'))
end
function write_wkt(io, ::GI.AbstractLineStringTrait, g)
    return (print(io, "LINESTRING "); points_text(io, g))
end
write_wkt(io, ::GI.PolygonTrait, g) = (print(io, "POLYGON "); polygon_text(io, g))

function write_wkt(io, ::GI.MultiPointTrait, g)
    print(io, "MULTIPOINT ")
    return children_text(
        io, g, (io, p) -> (print(io, '('); point_text(io, p); print(io, ')'))
    )
end

function write_wkt(io, ::GI.MultiLineStringTrait, g)
    print(io, "MULTILINESTRING ")
    return children_text(io, g, points_text)
end

function write_wkt(io, ::GI.MultiPolygonTrait, g)
    print(io, "MULTIPOLYGON ")
    return children_text(io, g, polygon_text)
end

function write_wkt(io, ::GI.GeometryCollectionTrait, g)
    print(io, "GEOMETRYCOLLECTION ")
    return children_text(io, g, (io, c) -> write_wkt(io, GI.geomtrait(c), c))
end

function write_wkt(io, trait, g)
    throw(
        OBISValidationError(
            :geometry,
            typeof(g),
            "Geometries of type $(nameof(typeof(trait))) cannot be written as WKT for OBIS.",
        ),
    )
end

end

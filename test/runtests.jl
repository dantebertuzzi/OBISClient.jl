using Test
using Dates
using JSON3
using Tables
using DataFrames
using DuckDB
using OBISClient

include("mock.jl")

@testset "OBISClient.jl" begin
    @testset "parameters" begin
        include("test_params.jl")
    end
    @testset "schema" begin
        include("test_schema.jl")
    end
    @testset "http" begin
        include("test_http.jl")
    end
    @testset "occurrence" begin
        include("test_occurrence.jl")
    end
    @testset "pagination" begin
        include("test_pagination.jl")
    end
    @testset "tables" begin
        include("test_tables.jl")
    end
    @testset "citation and licences" begin
        include("test_citation.jl")
    end
    @testset "other endpoints" begin
        include("test_endpoints.jl")
    end
    @testset "spatial" begin
        include("test_spatial.jl")
    end
    @testset "cache" begin
        include("test_cache.jl")
    end
    @testset "access routes" begin
        include("test_routes.jl")
    end
    @testset "reading the bulk export" begin
        include("test_export_read.jl")
    end
    @testset "quality" begin
        include("test_aqua.jl")
    end
end

using Test
using WasmMakie

@testset "WasmMakie scaffold" begin
    @test WasmMakie isa Module
    @test pkgversion(WasmMakie) == v"0.0.1"
    # Host-agnostic guarantee: no web-framework or notebook-system reference
    # may ever appear in src/. This test is the enforcement.
    src_dir = joinpath(dirname(@__DIR__), "src")
    banned = ["Therapy", "Pluto", "Sessions.jl", "PlutoIslands"]
    for (root, _, files) in walkdir(src_dir), f in files
        endswith(f, ".jl") || continue
        content = read(joinpath(root, f), String)
        for word in banned
            @test !occursin(word, content)
        end
    end
end

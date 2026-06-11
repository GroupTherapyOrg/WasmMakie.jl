# Reference-suite runner for CanvasMakie.
#
# Runs Makie's upstream `@reference_test` scripts (fetched verbatim at the
# pinned tag into reftests/vendor_upstream/tests/) against CanvasMakie and
# scores the recorded PNGs against the official reference images with the
# vendored tile scorer. This is the host_refpass metric.
#
# The runner is a minimal reimplementation of ReferenceTests/src/database.jl's
# recording side (same theme, same StableRNG seeding — seeds MUST match or
# random test data diverges from the reference images) without the MacroTools
# scan; skipping is by explicit title/predicate lists. Videos and other
# non-Figure results record as :unsupported rather than erroring the run.
module RefSuite

using Makie
using CanvasMakie
import PNGFiles
import Tar
import Downloads
# namespaces the upstream test scripts expect (mirrors ReferenceTests.jl usings)
using Makie.GeometryBasics
using Makie.Colors
using StructArrays
import DelimitedFiles: readdlm
import Makie.FileIO
using Test
using LinearAlgebra: normalize
import Makie.FileIO: load
using Makie: loadasset
import Distributions
using Unitful
using CategoricalArrays
using DelaunayTriangulation
import SparseArrays: sparse
using LinearAlgebra: norm

# RNG: vendored verbatim from ReferenceTests/src/stable_rng.jl (MIT)
module RNG
    using StableRNGs
    using Makie.Colors
    using Random

    const STABLE_RNG = StableRNG(123)

    rand(args...) = Base.rand(STABLE_RNG, args...)
    randn(args...) = Base.randn(STABLE_RNG, args...)

    seed_rng!() = Random.seed!(STABLE_RNG, 123)

    function Base.rand(r::StableRNGs.LehmerRNG, ::Random.SamplerType{T}) where {T <: ColorAlpha}
        return T(Base.rand(r), Base.rand(r), Base.rand(r), Base.rand(r))
    end

    function Base.rand(r::StableRNGs.LehmerRNG, ::Random.SamplerType{T}) where {T <: AbstractRGB}
        return T(Base.rand(r), Base.rand(r), Base.rand(r))
    end
end
using .RNG

mutable struct TestResult
    title::String
    status::Symbol   # :recorded | :error | :skipped | :unsupported
    detail::String
end

const RESULTS = TestResult[]
const RECORDING_DIR = Ref("")
const SKIP_TITLES = Set{String}()
# substring scan over test source — the 2D-target skip list (mesh/3D family),
# mirroring upstream's SKIP_FUNCTIONS mechanism
const SKIP_PATTERNS = Ref(String[])

macro reference_test(name, code)
    title = string(name)
    codestr = string(code)
    return quote
        _run_reference_test($(title), $(codestr)) do
            $(esc(code))
        end
    end
end

function _run_reference_test(f, title::String, codestr::String = "")
    if title in SKIP_TITLES
        push!(RESULTS, TestResult(title, :skipped, "skip list"))
        return
    end
    for p in SKIP_PATTERNS[]
        if occursin(p, codestr)
            push!(RESULTS, TestResult(title, :skipped, "skip pattern: $p"))
            return
        end
    end
    # upstream recording theme (database.jl), adapted to this backend
    Makie.set_theme!(; size = (500, 500), CanvasMakie = (; px_per_unit = 1))
    RNG.seed_rng!()
    result = try
        f()
    catch e
        push!(RESULTS, TestResult(title, :error, sprint(showerror, e)[1:min(end, 300)]))
        return
    end
    if result isa Makie.FigureLike || result isa Makie.Scene
        try
            img = Makie.colorbuffer(result)
            PNGFiles.save(joinpath(RECORDING_DIR[], title * ".png"), img)
            push!(RESULTS, TestResult(title, :recorded, ""))
        catch e
            push!(RESULTS, TestResult(title, :error, sprint(showerror, e)[1:min(end, 300)]))
        end
    else
        push!(RESULTS, TestResult(title, :unsupported, "result type $(typeof(result)) (video/steps?)"))
    end
    return
end

"""
    run_file(path; recording_dir, skip = String[])

Run one upstream reference-test file. Returns the slice of RESULTS it produced.
"""
function run_file(path::String; recording_dir::String, skip::Vector{String} = String[])
    empty!(SKIP_TITLES)
    union!(SKIP_TITLES, skip)
    RECORDING_DIR[] = recording_dir
    mkpath(recording_dir)
    CanvasMakie.activate!()
    n0 = length(RESULTS)
    Base.include(@__MODULE__, path)
    Makie.set_theme!()  # reset
    return RESULTS[(n0 + 1):end]
end

"""
    report(results, scores; threshold = 0.05) -> NamedTuple

Combine run statuses with image scores into the refpass summary.
"""
function report(results::Vector{TestResult}, scores::Dict{String,Float64}; threshold::Float64 = 0.05)
    recorded = count(r -> r.status === :recorded, results)
    errored = count(r -> r.status === :error, results)
    unsupported = count(r -> r.status === :unsupported, results)
    skipped = count(r -> r.status === :skipped, results)
    passed = count(s -> s <= threshold, values(scores))
    total = length(results) - skipped
    return (; passed, scored = length(scores), recorded, errored, unsupported, skipped,
            total, rate = total == 0 ? 0.0 : passed / total)
end

end # module

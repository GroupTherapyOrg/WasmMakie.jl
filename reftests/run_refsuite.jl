# Reference-suite driver — the host_refpass metric.
#
#   julia +1.12 --project=CanvasMakie/test reftests/run_refsuite.jl [file ...]
#
# Runs the named upstream test files (default: short_tests) through CanvasMakie,
# scores recordings against the official CairoMakie reference images, writes
# reftests/scores_<file>.tsv (committed — the burn-down ledger), and prints the
# REFPASS summary line per file.
using Makie, CanvasMakie

include(joinpath(@__DIR__, "refsuite.jl"))
include(joinpath(@__DIR__, "scorer.jl"))

const REFDIR = joinpath(@__DIR__, "reference_images", "extracted", "CairoMakie")
isdir(REFDIR) || error("reference images not extracted — run RefScorer.fetch flow first")

files = isempty(ARGS) ? ["short_tests"] : ARGS

# the 2D-target skip list: mesh/3D/volume territory (plan R-005 / out of scope)
# R-006: band/2D-mesh now render (CanvasMakie mesh path); 3D stays skipped
RefSuite.SKIP_PATTERNS[] = String[
    "meshscatter", "surface(", "surface!", "volume", "voxel",
    "Axis3", "tricontourf", "contour3d", "wireframe",
    "arrows3d", "LScene", "matcap", "uv_mesh", "Stepper",
]

for name in files
    file = joinpath(@__DIR__, "vendor_upstream", "tests", name * ".jl")
    isfile(file) || error("no vendored test file: $file")
    rec = joinpath(@__DIR__, "recorded", name)
    rm(rec; recursive = true, force = true)

    results = RefSuite.run_file(file; recording_dir = rec)

    scores = Dict{String,Float64}()
    for r in results
        r.status === :recorded || continue
        refpng = joinpath(REFDIR, r.title * ".png")
        if isfile(refpng)
            scores[r.title] = Float64(RefScorer.compare_media(joinpath(rec, r.title * ".png"), refpng))
        else
            r.status = :unsupported
            r.detail = "no reference image for this backend/version"
        end
    end

    rep = RefSuite.report(results, scores)
    open(joinpath(@__DIR__, "scores_$(name).tsv"), "w") do io
        println(io, "# status\tscore\ttitle\tdetail")
        for r in sort(results; by = r -> (r.status, -get(scores, r.title, Inf)))
            s = get(scores, r.title, nothing)
            println(io, r.status, '\t', s === nothing ? "-" : round(s, digits = 4), '\t',
                    r.title, '\t', replace(r.detail, '\n' => ' '))
        end
        println(io, "# REFPASS passed=$(rep.passed)/$(rep.total) scored=$(rep.scored) recorded=$(rep.recorded) errored=$(rep.errored) unsupported=$(rep.unsupported) rate=$(round(rep.rate, digits = 3))")
    end
    println("REFPASS $(name): passed=$(rep.passed)/$(rep.total) (scored=$(rep.scored), recorded=$(rep.recorded), errored=$(rep.errored), unsupported=$(rep.unsupported)) rate=$(round(rep.rate, digits = 3))")
end

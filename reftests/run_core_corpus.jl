# Core-corpus driver — the core_parity corpus metric (plan C-010).
#
#   julia +1.12 --project=CanvasMakie/test reftests/run_core_corpus.jl
#
# Renders every corpus scene through BOTH the static core (RecordingCtx →
# Chromium) and real Makie (CanvasMakie screen), scores the pairs with the
# vendored tile scorer, writes reftests/scores_core_corpus.tsv and prints the
# CORE_PARITY summary.
using Makie, CanvasMakie
import WasmMakie
import PNGFiles

include(joinpath(@__DIR__, "scorer.jl"))
include(joinpath(@__DIR__, "core_corpus.jl"))

const W = 400
const H = 300

CanvasMakie.activate!()

results = Tuple{String,Float64}[]
for scene in CoreCorpus.CORPUS
    # static core
    wfig = WasmMakie.Figure(size = (W, H))
    scene.build_core(wfig)
    rctx = WasmMakie.RecordingCtx()
    WasmMakie.render!(wfig, rctx)
    img_w = PNGFiles.load(IOBuffer(CanvasMakie.commands_to_png(rctx, W, H)))

    # real Makie
    mfig = Makie.Figure(size = (W, H))
    scene.build_makie(Makie, mfig)
    img_m = Makie.colorbuffer(mfig)

    score = Float64(RefScorer.compare_images(img_w, img_m))
    push!(results, (scene.name, score))
    println(rpad(scene.name, 30), " score=", round(score, digits = 4))
end

open(joinpath(@__DIR__, "scores_core_corpus.tsv"), "w") do io
    println(io, "# score\tscene  (static core vs real-Makie CanvasMakie render)")
    for (name, score) in sort(results; by = last, rev = true)
        println(io, round(score, digits = 4), '\t', name)
    end
    passed = count(r -> r[2] <= 0.35, results)
    println(io, "# CORE_PARITY passed=$(passed)/$(length(results)) @ loose tier 0.35 (T-004 tightens)")
end
passed = count(r -> r[2] <= 0.35, results)
println("CORE_PARITY: $(passed)/$(length(results)) @ 0.35  worst=$(round(maximum(last.(results)), digits = 4))")

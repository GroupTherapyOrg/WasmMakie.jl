# W-006 stage 2 — score the stage-1 wasm-rendered corpus PNGs against real
# Makie renders of the same scenes (same pairing as run_core_corpus.jl).
#
#   julia +1.12 --project=CanvasMakie/test reftests/run_wasm_corpus_stage2.jl
#
# Writes reftests/scores_wasm_corpus.tsv and prints the WASM_REFPASS summary.
using Makie, CanvasMakie
import PNGFiles

include(joinpath(@__DIR__, "scorer.jl"))

const W = 400
const H = 300
const TIER = 0.35   # same loose tier as core_parity until T-004

CanvasMakie.activate!()

# (slug, build_makie) — MUST mirror reftests/wasm_corpus.jl kernel order,
# which itself mirrors CoreCorpus.CORPUS.
XS = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
YS1 = [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5]
YS2 = [0.9, 0.2, 0.6, 0.1, 0.7, 0.3, 0.6]

scenes = [
    ("01_single_line", fig -> lines!(Axis(fig[1, 1]), XS, YS1)),
    ("02_two_lines_cycle", fig -> (ax = Axis(fig[1, 1]); lines!(ax, XS, YS1); lines!(ax, XS, YS2))),
    ("03_thick_red_line", fig -> lines!(Axis(fig[1, 1]), XS, YS1; color = :red, linewidth = 6.0)),
    ("04_dashed_line", fig -> lines!(Axis(fig[1, 1]), XS, YS1; linestyle = :dash, linewidth = 3.0)),
    ("05_scatter_default", fig -> scatter!(Axis(fig[1, 1]), XS, YS1)),
    ("06_scatter_sized_rect", fig -> scatter!(Axis(fig[1, 1]), XS, YS1;
                                              marker = :rect, markersize = 18, color = :purple)),
    ("07_lines_plus_scatter", fig -> (ax = Axis(fig[1, 1]); lines!(ax, XS, YS1);
                                      scatter!(ax, XS, YS1; color = :red, markersize = 12))),
    ("08_barplot", fig -> barplot!(Axis(fig[1, 1]), [1, 2, 3, 4], [3.0, 5.0, 2.0, 4.0])),
    ("09_barplot_negative", fig -> barplot!(Axis(fig[1, 1]), [1, 2, 3], [2.0, -1.5, 3.0]; color = :orange)),
    ("10_heatmap_viridis", fig -> heatmap!(Axis(fig[1, 1]), [0, 1, 2, 3], [0, 1, 2],
                                           [1.0 4.0; 2.0 5.0; 3.0 6.0])),
    ("11_image_primaries", fig -> image!(Axis(fig[1, 1]), Makie.:(..)(0, 2), Makie.:(..)(0, 2),
                                         [Makie.RGBAf(1, 0, 0, 1) Makie.RGBAf(0, 1, 0, 1);
                                          Makie.RGBAf(0, 0, 1, 1) Makie.RGBAf(1, 1, 0, 1)];
                                         interpolate = false)),
    ("12_titles_and_labels", fig -> lines!(Axis(fig[1, 1]; title = "Title",
                                                xlabel = "the x axis", ylabel = "the y axis"), XS, YS1)),
    ("13_grid_2x2", fig -> (lines!(Axis(fig[1, 1]), XS, YS1);
                            scatter!(Axis(fig[1, 2]), XS, YS2);
                            barplot!(Axis(fig[2, 1]), [1, 2, 3], [1.0, 2.0, 1.5]);
                            lines!(Axis(fig[2, 2]), XS, YS2; color = :green))),
]

recdir = joinpath(@__DIR__, "recorded", "wasm_corpus")
results = Tuple{String,Float64}[]
for (slug, build) in scenes
    png_path = joinpath(recdir, slug * ".png")
    if !isfile(png_path)
        println(rpad(slug, 26), " MISSING stage-1 png")
        push!(results, (slug, Inf))
        continue
    end
    img_w = PNGFiles.load(png_path)
    mfig = Makie.Figure(size = (W, H))
    build(mfig)
    img_m = Makie.colorbuffer(mfig)
    score = Float64(RefScorer.compare_images(img_w, img_m))
    push!(results, (slug, score))
    println(rpad(slug, 26), " score=", round(score, digits = 4))
end

open(joinpath(@__DIR__, "scores_wasm_corpus.tsv"), "w") do io
    println(io, "# score\tscene  (wasm Chromium render vs real-Makie CanvasMakie render)")
    for (name, score) in sort(results; by = last, rev = true)
        println(io, round(score, digits = 4), '\t', name)
    end
    passed = count(r -> r[2] <= TIER, results)
    println(io, "# WASM_REFPASS passed=$(passed)/$(length(results)) @ loose tier $(TIER) (T-004 tightens)")
end
passed = count(r -> r[2] <= TIER, results)
println("WASM_REFPASS: $(passed)/$(length(results)) @ $(TIER)  worst=$(round(maximum(last.(results)), digits = 4))")

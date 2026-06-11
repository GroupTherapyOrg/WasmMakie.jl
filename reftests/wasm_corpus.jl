# W-006: the C-010 corpus as wasm-compilable kernels.
#
# Each kernel is a TOP-LEVEL function mirroring one CoreCorpus scene's
# build_core closure (closures don't compile through WasmTarget). Data
# vectors are inlined literals — const-global non-isbits references trap
# (WTGAP ffd3d052c6a4, fixed upstream but not yet in the pinned checkout).
# heatmap/image use the flat-vector overloads (WTGAP 3aaa51b9a688).
#
# Kernel order/names MUST match CoreCorpus.CORPUS so stage-2 scoring pairs up.
module WasmCorpus

using WasmMakie

# XS = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
# YS1 = [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5]
# YS2 = [0.9, 0.2, 0.6, 0.1, 0.7, 0.3, 0.6]

function k01_single_line()
    fig = Figure(size = (400.0, 300.0))
    lines!(Axis(fig[1, 1]),
           [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
           [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5])
    render!(fig, WasmCtx()); return Int64(0)
end

function k02_two_lines_cycle()
    fig = Figure(size = (400.0, 300.0))
    ax = Axis(fig[1, 1])
    lines!(ax, [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
               [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5])
    lines!(ax, [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
               [0.9, 0.2, 0.6, 0.1, 0.7, 0.3, 0.6])
    render!(fig, WasmCtx()); return Int64(0)
end

function k03_thick_red_line()
    fig = Figure(size = (400.0, 300.0))
    lines!(Axis(fig[1, 1]),
           [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
           [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5];
           color = :red, linewidth = 6.0)
    render!(fig, WasmCtx()); return Int64(0)
end

function k04_dashed_line()
    fig = Figure(size = (400.0, 300.0))
    lines!(Axis(fig[1, 1]),
           [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
           [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5];
           linestyle = :dash, linewidth = 3.0)
    render!(fig, WasmCtx()); return Int64(0)
end

function k05_scatter_default()
    fig = Figure(size = (400.0, 300.0))
    scatter!(Axis(fig[1, 1]),
             [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
             [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5])
    render!(fig, WasmCtx()); return Int64(0)
end

function k06_scatter_sized_rect()
    fig = Figure(size = (400.0, 300.0))
    scatter!(Axis(fig[1, 1]),
             [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
             [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5];
             marker = :rect, markersize = 18.0, color = :purple)
    render!(fig, WasmCtx()); return Int64(0)
end

function k07_lines_plus_scatter()
    fig = Figure(size = (400.0, 300.0))
    ax = Axis(fig[1, 1])
    lines!(ax, [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
               [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5])
    scatter!(ax, [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
                 [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5];
                 color = :red, markersize = 12.0)
    render!(fig, WasmCtx()); return Int64(0)
end

function k08_barplot()
    fig = Figure(size = (400.0, 300.0))
    barplot!(Axis(fig[1, 1]), [1.0, 2.0, 3.0, 4.0], [3.0, 5.0, 2.0, 4.0])
    render!(fig, WasmCtx()); return Int64(0)
end

function k09_barplot_negative()
    fig = Figure(size = (400.0, 300.0))
    barplot!(Axis(fig[1, 1]), [1.0, 2.0, 3.0], [2.0, -1.5, 3.0]; color = :orange)
    render!(fig, WasmCtx()); return Int64(0)
end

function k10_heatmap_viridis()
    fig = Figure(size = (400.0, 300.0))
    # [1.0 4.0; 2.0 5.0; 3.0 6.0] (3×2) column-major flat
    heatmap!(Axis(fig[1, 1]), [0.0, 1.0, 2.0, 3.0], [0.0, 1.0, 2.0],
             [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], Int64(3), Int64(2))
    render!(fig, WasmCtx()); return Int64(0)
end

function k11_image_primaries()
    fig = Figure(size = (400.0, 300.0))
    # [(red) (green); (blue) (yellow)] (2×2) column-major flat
    px = NTuple{4,Float64}[(1.0, 0.0, 0.0, 1.0), (0.0, 0.0, 1.0, 1.0),
                           (0.0, 1.0, 0.0, 1.0), (1.0, 1.0, 0.0, 1.0)]
    image!(Axis(fig[1, 1]), (0.0, 2.0), (0.0, 2.0), px, Int64(2), Int64(2);
           interpolate = false)
    render!(fig, WasmCtx()); return Int64(0)
end

function k12_titles_and_labels()
    fig = Figure(size = (400.0, 300.0))
    lines!(Axis(fig[1, 1]; title = "Title",
                xlabel = "the x axis", ylabel = "the y axis"),
           [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
           [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5])
    render!(fig, WasmCtx()); return Int64(0)
end

function k13_grid_2x2()
    fig = Figure(size = (400.0, 300.0))
    lines!(Axis(fig[1, 1]), [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
                            [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5])
    scatter!(Axis(fig[1, 2]), [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
                              [0.9, 0.2, 0.6, 0.1, 0.7, 0.3, 0.6])
    barplot!(Axis(fig[2, 1]), [1.0, 2.0, 3.0], [1.0, 2.0, 1.5])
    lines!(Axis(fig[2, 2]), [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
                            [0.9, 0.2, 0.6, 0.1, 0.7, 0.3, 0.6]; color = :green)
    render!(fig, WasmCtx()); return Int64(0)
end

"(slug, kernel) in CoreCorpus.CORPUS order."
const KERNELS = [
    ("01_single_line", k01_single_line),
    ("02_two_lines_cycle", k02_two_lines_cycle),
    ("03_thick_red_line", k03_thick_red_line),
    ("04_dashed_line", k04_dashed_line),
    ("05_scatter_default", k05_scatter_default),
    ("06_scatter_sized_rect", k06_scatter_sized_rect),
    ("07_lines_plus_scatter", k07_lines_plus_scatter),
    ("08_barplot", k08_barplot),
    ("09_barplot_negative", k09_barplot_negative),
    ("10_heatmap_viridis", k10_heatmap_viridis),
    ("11_image_primaries", k11_image_primaries),
    ("12_titles_and_labels", k12_titles_and_labels),
    ("13_grid_2x2", k13_grid_2x2),
]

end # module

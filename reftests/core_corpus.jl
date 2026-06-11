# The static-core scene corpus — Track B's climbing metric (plan C-010).
#
# Each scene is built TWICE: through WasmMakie's static core and through real
# Makie (rendered by CanvasMakie). The tile scorer compares the two — that is
# the core_parity corpus. Where a scene also matches an official reference
# test title, the official image is scored too (recorded; expected to pass
# only once T-004 exact text extents land).
#
# Scenes are 400×300 px_per_unit 1 unless noted. Add scenes as the core API
# grows; never delete (the ledger is a ratchet).
module CoreCorpus

import WasmMakie

struct Scene2
    name::String
    build_core::Function    # (fig::WasmMakie.Figure) -> nothing
    build_makie::Function   # (fig::Makie.Figure) -> nothing  (evaluated in caller scope)
end

const XS = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
const YS1 = [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5]
const YS2 = [0.9, 0.2, 0.6, 0.1, 0.7, 0.3, 0.6]

const CORPUS = Scene2[
    Scene2("core: single line",
        fig -> WasmMakie.lines!(WasmMakie.Axis(fig[1, 1]), XS, YS1),
        (Makie, fig) -> Makie.lines!(Makie.Axis(fig[1, 1]), XS, YS1)),
    Scene2("core: two lines cycle",
        fig -> (ax = WasmMakie.Axis(fig[1, 1]);
                WasmMakie.lines!(ax, XS, YS1); WasmMakie.lines!(ax, XS, YS2)),
        (Makie, fig) -> (ax = Makie.Axis(fig[1, 1]);
                Makie.lines!(ax, XS, YS1); Makie.lines!(ax, XS, YS2))),
    Scene2("core: thick red line",
        fig -> WasmMakie.lines!(WasmMakie.Axis(fig[1, 1]), XS, YS1;
                                color = :red, linewidth = 6.0),
        (Makie, fig) -> Makie.lines!(Makie.Axis(fig[1, 1]), XS, YS1;
                                     color = :red, linewidth = 6.0)),
    Scene2("core: dashed line",
        fig -> WasmMakie.lines!(WasmMakie.Axis(fig[1, 1]), XS, YS1;
                                linestyle = :dash, linewidth = 3.0),
        (Makie, fig) -> Makie.lines!(Makie.Axis(fig[1, 1]), XS, YS1;
                                     linestyle = :dash, linewidth = 3.0)),
    Scene2("core: scatter default",
        fig -> WasmMakie.scatter!(WasmMakie.Axis(fig[1, 1]), XS, YS1),
        (Makie, fig) -> Makie.scatter!(Makie.Axis(fig[1, 1]), XS, YS1)),
    Scene2("core: scatter sized rect",
        fig -> WasmMakie.scatter!(WasmMakie.Axis(fig[1, 1]), XS, YS1;
                                  marker = :rect, markersize = 18.0, color = :purple),
        (Makie, fig) -> Makie.scatter!(Makie.Axis(fig[1, 1]), XS, YS1;
                                       marker = :rect, markersize = 18, color = :purple)),
    Scene2("core: lines + scatter",
        fig -> (ax = WasmMakie.Axis(fig[1, 1]);
                WasmMakie.lines!(ax, XS, YS1);
                WasmMakie.scatter!(ax, XS, YS1; color = :red, markersize = 12.0)),
        (Makie, fig) -> (ax = Makie.Axis(fig[1, 1]);
                Makie.lines!(ax, XS, YS1);
                Makie.scatter!(ax, XS, YS1; color = :red, markersize = 12))),
    Scene2("core: barplot",
        fig -> WasmMakie.barplot!(WasmMakie.Axis(fig[1, 1]), [1, 2, 3, 4], [3.0, 5.0, 2.0, 4.0]),
        (Makie, fig) -> Makie.barplot!(Makie.Axis(fig[1, 1]), [1, 2, 3, 4], [3.0, 5.0, 2.0, 4.0])),
    Scene2("core: barplot negative",
        fig -> WasmMakie.barplot!(WasmMakie.Axis(fig[1, 1]), [1, 2, 3], [2.0, -1.5, 3.0]; color = :orange),
        (Makie, fig) -> Makie.barplot!(Makie.Axis(fig[1, 1]), [1, 2, 3], [2.0, -1.5, 3.0]; color = :orange)),
    Scene2("core: heatmap viridis",
        fig -> WasmMakie.heatmap!(WasmMakie.Axis(fig[1, 1]), [0, 1, 2, 3], [0, 1, 2],
                                  [1.0 4.0; 2.0 5.0; 3.0 6.0]),
        (Makie, fig) -> Makie.heatmap!(Makie.Axis(fig[1, 1]), [0, 1, 2, 3], [0, 1, 2],
                                       [1.0 4.0; 2.0 5.0; 3.0 6.0])),
    Scene2("core: image primaries",
        fig -> WasmMakie.image!(WasmMakie.Axis(fig[1, 1]), (0.0, 2.0), (0.0, 2.0),
                                [(1.0, 0.0, 0.0, 1.0) (0.0, 1.0, 0.0, 1.0);
                                 (0.0, 0.0, 1.0, 1.0) (1.0, 1.0, 0.0, 1.0)];
                                interpolate = false),
        (Makie, fig) -> Makie.image!(Makie.Axis(fig[1, 1]), Makie.:(..)(0, 2), Makie.:(..)(0, 2),
                                     [Makie.RGBAf(1, 0, 0, 1) Makie.RGBAf(0, 1, 0, 1);
                                      Makie.RGBAf(0, 0, 1, 1) Makie.RGBAf(1, 1, 0, 1)];
                                     interpolate = false)),
    Scene2("core: titles and labels",
        fig -> WasmMakie.lines!(WasmMakie.Axis(fig[1, 1]; title = "Title",
                                xlabel = "the x axis", ylabel = "the y axis"), XS, YS1),
        (Makie, fig) -> Makie.lines!(Makie.Axis(fig[1, 1]; title = "Title",
                                xlabel = "the x axis", ylabel = "the y axis"), XS, YS1)),
    Scene2("core: 2x2 grid",
        fig -> (WasmMakie.lines!(WasmMakie.Axis(fig[1, 1]), XS, YS1);
                WasmMakie.scatter!(WasmMakie.Axis(fig[1, 2]), XS, YS2);
                WasmMakie.barplot!(WasmMakie.Axis(fig[2, 1]), [1, 2, 3], [1.0, 2.0, 1.5]);
                WasmMakie.lines!(WasmMakie.Axis(fig[2, 2]), XS, YS2; color = :green)),
        (Makie, fig) -> (Makie.lines!(Makie.Axis(fig[1, 1]), XS, YS1);
                Makie.scatter!(Makie.Axis(fig[1, 2]), XS, YS2);
                Makie.barplot!(Makie.Axis(fig[2, 1]), [1, 2, 3], [1.0, 2.0, 1.5]);
                Makie.lines!(Makie.Axis(fig[2, 2]), XS, YS2; color = :green))),
    Scene2("axis: hidden decorations + spines",
        fig -> (ax = WasmMakie.Axis(fig[1, 1]);
                WasmMakie.lines!(ax, XS, YS1);
                WasmMakie.hidedecorations!(ax); WasmMakie.hidespines!(ax)),
        (Makie, fig) -> (ax = Makie.Axis(fig[1, 1]);
                Makie.lines!(ax, XS, YS1);
                Makie.hidedecorations!(ax); Makie.hidespines!(ax))),
    Scene2("axis: minorgrid + bold title + subtitle",
        fig -> (ax = WasmMakie.Axis(fig[1, 1]; title = "Title", subtitle = "Sub");
                ax.xminorgridvisible = true; ax.yminorgridvisible = true;
                WasmMakie.lines!(ax, XS, YS1)),
        (Makie, fig) -> (ax = Makie.Axis(fig[1, 1]; title = "Title", subtitle = "Sub",
                                         xminorgridvisible = true, yminorgridvisible = true);
                Makie.lines!(ax, XS, YS1))),
    Scene2("legend: axislegend rt",
        fig -> (ax = WasmMakie.Axis(fig[1, 1]);
                WasmMakie.lines!(ax, XS, YS1; label = "one");
                WasmMakie.scatter!(ax, XS, YS2; label = "two", color = :red, markersize = 10.0);
                WasmMakie.axislegend(ax)),
        (Makie, fig) -> (ax = Makie.Axis(fig[1, 1]);
                Makie.lines!(ax, XS, YS1; label = "one");
                Makie.scatter!(ax, XS, YS2; label = "two", color = :red, markersize = 10);
                Makie.axislegend(ax))),
    Scene2("colorbar: heatmap-linked vertical",
        fig -> (hm = WasmMakie.heatmap!(WasmMakie.Axis(fig[1, 1]), [0, 1, 2, 3], [0, 1, 2],
                                        [1.0 4.0; 2.0 5.0; 3.0 6.0]);
                WasmMakie.Colorbar(fig[1, 2], hm)),
        (Makie, fig) -> (hm = Makie.heatmap!(Makie.Axis(fig[1, 1]), [0, 1, 2, 3], [0, 1, 2],
                                             [1.0 4.0; 2.0 5.0; 3.0 6.0]);
                Makie.Colorbar(fig[1, 2], hm))),
    Scene2("layout: span + relative colsize",
        fig -> (WasmMakie.lines!(WasmMakie.Axis(fig[1, 1:2]; title = "wide"), XS, YS1);
                WasmMakie.scatter!(WasmMakie.Axis(fig[2, 1]), XS, YS2);
                WasmMakie.barplot!(WasmMakie.Axis(fig[2, 2]), [1, 2, 3], [1.0, 2.0, 1.5]);
                WasmMakie.colsize!(fig, 1, WasmMakie.Relative(0.35))),
        (Makie, fig) -> (Makie.lines!(Makie.Axis(fig[1, 1:2]; title = "wide"), XS, YS1);
                Makie.scatter!(Makie.Axis(fig[2, 1]), XS, YS2);
                Makie.barplot!(Makie.Axis(fig[2, 2]), [1, 2, 3], [1.0, 2.0, 1.5]);
                Makie.colsize!(fig.layout, 1, Makie.Relative(0.35)))),
    Scene2("recipes: wave-1 annotations",
        fig -> (ax = WasmMakie.Axis(fig[1, 1]);
                WasmMakie.lines!(ax, XS, YS1);
                WasmMakie.hlines!(ax, [0.5]; color = :red);
                WasmMakie.vlines!(ax, [1.5]; color = :green, linestyle = :dash);
                WasmMakie.hspan!(ax, 0.1, 0.25; color = (0.2, 0.4, 0.8, 0.3));
                WasmMakie.vspan!(ax, 2.4, 2.8; color = (0.8, 0.4, 0.2, 0.3));
                WasmMakie.ablines!(ax, 0.0, 0.3; color = :purple);
                WasmMakie.linesegments!(ax, [0.2, 0.8, 1.8, 2.4], [0.85, 0.85, 0.15, 0.15]; color = :black)),
        (Makie, fig) -> (ax = Makie.Axis(fig[1, 1]);
                Makie.lines!(ax, XS, YS1);
                Makie.hlines!(ax, [0.5]; color = :red);
                Makie.vlines!(ax, [1.5]; color = :green, linestyle = :dash);
                Makie.hspan!(ax, 0.1, 0.25; color = (:blue, 0.3) === nothing ? :blue : Makie.RGBAf(0.2, 0.4, 0.8, 0.3));
                Makie.vspan!(ax, 2.4, 2.8; color = Makie.RGBAf(0.8, 0.4, 0.2, 0.3));
                Makie.ablines!(ax, 0.0, 0.3; color = :purple);
                Makie.linesegments!(ax, [0.2, 0.8, 1.8, 2.4], [0.85, 0.85, 0.15, 0.15]; color = :black))),
    Scene2("recipes: scatterlines",
        fig -> WasmMakie.scatterlines!(WasmMakie.Axis(fig[1, 1]), XS, YS1; markersize = 10.0),
        (Makie, fig) -> Makie.scatterlines!(Makie.Axis(fig[1, 1]), XS, YS1; markersize = 10)),
    Scene2("recipes: stairs pre",
        fig -> WasmMakie.stairs!(WasmMakie.Axis(fig[1, 1]), XS, YS1),
        (Makie, fig) -> Makie.stairs!(Makie.Axis(fig[1, 1]), XS, YS1)),
    Scene2("recipes: hist 8 bins",
        fig -> WasmMakie.hist!(WasmMakie.Axis(fig[1, 1]),
                               [0.1, 0.2, 0.2, 0.3, 0.45, 0.5, 0.5, 0.55, 0.7, 0.9]; bins = 8),
        (Makie, fig) -> Makie.hist!(Makie.Axis(fig[1, 1]),
                                    [0.1, 0.2, 0.2, 0.3, 0.45, 0.5, 0.5, 0.55, 0.7, 0.9]; bins = 8)),
    Scene2("recipes: stem + errorbars",
        fig -> (ax = WasmMakie.Axis(fig[1, 1]);
                WasmMakie.stem!(ax, [1.0, 2.0, 3.0, 4.0], [0.5, -0.3, 0.8, 0.2]);
                WasmMakie.errorbars!(ax, [1.0, 2.0, 3.0, 4.0], [0.5, -0.3, 0.8, 0.2],
                                     [0.15, 0.1, 0.2, 0.1]; color = :red)),
        (Makie, fig) -> (ax = Makie.Axis(fig[1, 1]);
                Makie.stem!(ax, [1.0, 2.0, 3.0, 4.0], [0.5, -0.3, 0.8, 0.2]);
                Makie.errorbars!(ax, [1.0, 2.0, 3.0, 4.0], [0.5, -0.3, 0.8, 0.2],
                                 [0.15, 0.1, 0.2, 0.1]; color = :red))),
    Scene2("recipes: pie",
        fig -> WasmMakie.pie!(WasmMakie.Axis(fig[1, 1]), [3.0, 2.0, 1.0];
                              colors = [:red, :green, :blue]),
        (Makie, fig) -> Makie.pie!(Makie.Axis(fig[1, 1]), [3.0, 2.0, 1.0];
                                   color = [:red, :green, :blue])),
    Scene2("recipes: boxplot",
        fig -> WasmMakie.boxplot!(WasmMakie.Axis(fig[1, 1]),
                                  [1.0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2],
                                  [1.0, 2, 3, 4, 5, 9, 2, 3, 3, 4, 5, 6]),
        (Makie, fig) -> Makie.boxplot!(Makie.Axis(fig[1, 1]),
                                       [1.0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2],
                                       [1.0, 2, 3, 4, 5, 9, 2, 3, 3, 4, 5, 6])),
    Scene2("recipes: violin",
        fig -> WasmMakie.violin!(WasmMakie.Axis(fig[1, 1]),
                                 [1.0, 1, 1, 1, 1, 2, 2, 2, 2, 2],
                                 [1.0, 2, 3, 4, 5, 2, 3, 3, 4, 5]),
        (Makie, fig) -> Makie.violin!(Makie.Axis(fig[1, 1]),
                                      [1.0, 1, 1, 1, 1, 2, 2, 2, 2, 2],
                                      [1.0, 2, 3, 4, 5, 2, 3, 3, 4, 5])),
    # NOTE: "recipes: density" and "recipes: band" corpus scenes are deferred —
    # the Makie versions lower to Band/mesh, which CanvasMakie draws after R-005.
]

end # module

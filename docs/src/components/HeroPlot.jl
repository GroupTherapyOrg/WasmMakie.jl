# Landing-page hero figure, rendered AT BUILD TIME by WasmMakie through the
# embedding contract — the page ships a recorded Canvas2D command stream +
# the replayer, not a screenshot. This snippet carries the document-wide
# FontFaces (fonts=true); it is the first figure on the landing page.
import WasmMakie as WM
using WasmMakie: lines!, scatter!, band!
using Therapy: RawHtml

function HeroPlot()
    fig = WM.Figure(size = (760.0, 340.0))
    ax = WM.Axis(fig[1, 1]; title = "rendered by WasmMakie, in your browser, right now",
                 xlabel = "x", ylabel = "y")
    xs = collect(0.0:0.04:6.3)
    ys = [sin(x) for x in xs]
    lo = [sin(x) - 0.25 - 0.06 * x for x in xs]
    hi = [sin(x) + 0.25 + 0.06 * x for x in xs]
    band!(ax, xs, lo, hi)
    lines!(ax, xs, ys; linewidth = 2.0)
    scatter!(ax, collect(0.5:0.7:6.0), [sin(x) for x in 0.5:0.7:6.0];
             color = :red, markersize = 9.0)
    Div(:class => "rounded-lg border border-warm-200 dark:border-warm-800 overflow-hidden bg-white gallery-canvas",
        RawHtml(WM.html_snippet(fig; fonts = true))
    )
end

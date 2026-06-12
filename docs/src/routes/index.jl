() -> begin
    Div(:class => "space-y-16",
        # Hero
        Div(:class => "text-center space-y-6 pt-8",
            H1(:class => "no-rule text-5xl md:text-6xl font-serif font-bold text-warm-900 dark:text-warm-100",
                "Makie plots"
            ),
            H1(:class => "no-rule text-5xl md:text-6xl font-serif font-bold text-accent-500",
                "in the browser, no server"
            ),
            P(:class => "text-lg text-warm-600 dark:text-warm-400 max-w-2xl mx-auto leading-relaxed",
                "The ",
                A(:href => "https://makie.org", :target => "_blank", :class => "text-accent-500 hover:text-accent-600 underline", "Makie"),
                " API — Figure, Axis, lines!, scatter!, heatmap!, 20+ recipes — compiled to ",
                "WebAssembly via ",
                A(:href => "https://github.com/GroupTherapyOrg/WasmTarget.jl", :target => "_blank", :class => "text-accent-500 hover:text-accent-600 underline", "WasmTarget.jl"),
                ", drawing to HTML Canvas2D. ",
                "No runtime download, no Pyodide, no server round-trips: a figure island is ~190 KB gzipped with ~2 ms redraws."
            ),
            Div(:class => "flex gap-4 justify-center pt-4",
                A(:href => "/WasmMakie.jl/getting-started/",
                    :class => "px-6 py-3 bg-accent-600 hover:bg-accent-700 text-white rounded-lg font-medium transition-colors",
                    "Get Started"
                ),
                A(:href => "/WasmMakie.jl/gallery/",
                    :class => "px-6 py-3 border border-warm-300 dark:border-warm-700 rounded-lg font-medium text-warm-700 dark:text-warm-300 hover:bg-warm-100 dark:hover:bg-warm-900 transition-colors",
                    "Gallery"
                )
            )
        ),
        # Live hero plot (build-time WasmMakie render — see components/HeroPlot.jl)
        Div(:class => "max-w-3xl mx-auto",
            HeroPlot(),
            P(:class => "text-xs text-warm-500 dark:text-warm-500 text-center pt-2",
                "Not a screenshot — a recorded Canvas2D command stream replayed by the bundled renderer. Right-click → Inspect."
            )
        ),
        # Two-layer architecture
        Div(:class => "max-w-3xl mx-auto space-y-6",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "Two layers, one draw path"),
            Div(:class => "grid grid-cols-1 md:grid-cols-2 gap-6",
                Div(:class => "border border-warm-200 dark:border-warm-800 rounded-lg p-6 bg-warm-100/50 dark:bg-warm-900/50",
                    H3(:class => "font-semibold mb-2 text-warm-900 dark:text-warm-100", "WasmMakie — the wasm core"),
                    P(:class => "text-warm-600 dark:text-warm-400 text-sm leading-relaxed",
                        "A typed static core with the Makie API surface that WasmTarget compiles to WasmGC. ",
                        "Figures render as Canvas2D command streams — host and wasm produce bit-identical streams (14/14 differential corpus)."
                    )
                ),
                Div(:class => "border border-warm-200 dark:border-warm-800 rounded-lg p-6 bg-warm-100/50 dark:bg-warm-900/50",
                    H3(:class => "font-semibold mb-2 text-warm-900 dark:text-warm-100", "CanvasMakie — the true backend"),
                    P(:class => "text-warm-600 dark:text-warm-400 text-sm leading-relaxed",
                        "A real Makie backend (Screen, colorbuffer, backend_show) sharing the same draw layer — ",
                        "149/166 (89.8%) on Makie's 2D reference tests. ",
                        A(:href => "https://github.com/GroupTherapyOrg/WasmMakie.jl/blob/main/CanvasMakie/CONFORMANCE.md", :target => "_blank",
                          :class => "text-accent-500 hover:text-accent-600 underline", "Conformance audit"),
                        "."
                    )
                )
            )
        ),
        # Quick example
        Div(:class => "max-w-3xl mx-auto space-y-4",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "Quick Example"),
            Pre(:class => "bg-warm-900 dark:bg-warm-950 text-warm-200 p-6 rounded-lg overflow-x-auto border border-warm-800",
                Code(:class => "language-julia text-sm font-mono", """import WasmMakie as WM
using WasmMakie: lines!, scatter!

fig = WM.Figure(size = (600.0, 400.0))
ax = WM.Axis(fig[1, 1]; title = "hello", xlabel = "x")
lines!(ax, xs, ys; linewidth = 2.0)

write("plot.html", WM.html_snippet(fig))   # self-contained fragment""")
            ),
            P(:class => "text-sm text-warm-500 dark:text-warm-500",
                "That fragment is exactly what the plots on this page are. See ",
                A(:href => "/WasmMakie.jl/embedding/", :class => "text-accent-500 hover:text-accent-600 underline", "Embedding"),
                " for the full host contract — including compiling figures to wasm for client-side reactivity."
            )
        ),
        # Where it runs
        Div(:class => "max-w-3xl mx-auto space-y-4",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "Already deployed"),
            Ul(:class => "list-disc pl-6 space-y-2 text-warm-600 dark:text-warm-400",
                Li(A(:href => "https://grouptherapyorg.github.io/Therapy.jl/examples/", :target => "_blank",
                     :class => "text-accent-500 hover:text-accent-600 underline", "Therapy.jl docs"),
                   " — an interactive 2×2 dashboard where three signals re-render four Makie plots client-side"),
                Li("PlutoIslands.jl — published Pluto notebooks whose figure cells stay reactive without a Julia server"),
                Li("This site — every plot, including the ", A(:href => "/WasmMakie.jl/gallery/", :class => "text-accent-500 hover:text-accent-600 underline", "32-scene gallery"), ", is WasmMakie output")
            )
        )
    )
end

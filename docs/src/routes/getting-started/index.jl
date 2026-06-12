() -> begin
    Div(:class => "space-y-10 max-w-3xl",
        H1(:class => "text-3xl font-serif font-bold text-warm-900 dark:text-warm-100", "Getting Started"),

        Div(:class => "space-y-4",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "Install"),
            P(:class => "text-warm-600 dark:text-warm-400",
                "WasmMakie has zero dependencies and registration in General is in flight. Until it lands:"),
            Pre(:class => "bg-warm-900 dark:bg-warm-950 text-warm-200 p-6 rounded-lg overflow-x-auto border border-warm-800",
                Code(:class => "language-julia text-sm font-mono",
                    """using Pkg
Pkg.add(url = "https://github.com/GroupTherapyOrg/WasmMakie.jl")""")
            ),
            P(:class => "text-warm-600 dark:text-warm-400",
                "Julia 1.12+. Rendering figures to HTML needs nothing else; compiling them to wasm additionally uses ",
                A(:href => "https://github.com/GroupTherapyOrg/WasmTarget.jl", :target => "_blank",
                  :class => "text-accent-500 hover:text-accent-600 underline", "WasmTarget.jl"),
                " (usually via a host framework — see below)."
            )
        ),

        Div(:class => "space-y-4",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "First figure"),
            P(:class => "text-warm-600 dark:text-warm-400",
                "The API is Makie's. One naming caveat when a host also exports HTML tags (like Therapy's ",
                Code(:class => "text-accent-500 font-mono", "Figure"),
                " element): import the package qualified."
            ),
            Pre(:class => "bg-warm-900 dark:bg-warm-950 text-warm-200 p-6 rounded-lg overflow-x-auto border border-warm-800",
                Code(:class => "language-julia text-sm font-mono",
                    """import WasmMakie as WM
using WasmMakie: lines!, scatter!, heatmap!, barplot!

fig = WM.Figure(size = (600.0, 400.0))
ax  = WM.Axis(fig[1, 1]; title = "waves", xlabel = "x", ylabel = "sin(x)")

xs = collect(0.0:0.05:6.3)
lines!(ax, xs, [sin(x) for x in xs]; linewidth = 2.0)
scatter!(ax, [1.0, 2.0, 3.0], [0.8, 0.9, 0.1]; color = :red)

# A self-contained HTML fragment: <canvas> + recorded command
# stream + replayer. Drop it into any page.
write("plot.html", WM.html_snippet(fig))""")
            ),
            P(:class => "text-warm-600 dark:text-warm-400",
                "Layout follows Makie's grid model: ",
                Code(:class => "text-accent-500 font-mono", "WM.Axis(fig[1, 2])"),
                " places a second axis in column 2, ",
                Code(:class => "text-accent-500 font-mono", "WM.Colorbar(fig[1, 2], hm)"),
                " attaches a colorbar to a heatmap. ",
                "Over 20 recipes ship today — the full set is on the ",
                A(:href => "/WasmMakie.jl/gallery/", :class => "text-accent-500 hover:text-accent-600 underline", "Gallery"),
                " page, each rendered live by the shipping pipeline."
            )
        ),

        Div(:class => "space-y-4",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "Numeric conventions"),
            P(:class => "text-warm-600 dark:text-warm-400",
                "WasmMakie's core is a typed subset of Julia so WasmTarget can compile it. Stick to concrete numeric types:"),
            Ul(:class => "list-disc pl-6 space-y-2 text-warm-600 dark:text-warm-400",
                Li(Code(:class => "text-accent-500 font-mono", "Float64"), " positions and sizes (", Code(:class => "text-accent-500 font-mono", "size = (600.0, 400.0)"), ", not ", Code(:class => "font-mono", "(600, 400)"), ")"),
                Li(Code(:class => "text-accent-500 font-mono", "Vector{Float64}"), " data vectors"),
                Li("Flat column-major values + edge vectors for ", Code(:class => "text-accent-500 font-mono", "heatmap!(ax, xs, ys, values, nx, ny)")),
                Li("Colors as symbols (", Code(:class => "text-accent-500 font-mono", ":red"), ") or RGB floats; unset attributes follow Makie's cycling")
            ),
            P(:class => "text-warm-600 dark:text-warm-400",
                "On the host (outside wasm) ordinary Julia works — these conventions only matter for code that gets compiled into an island."
            )
        ),

        Div(:class => "space-y-4",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "Interactive figures (wasm)"),
            P(:class => "text-warm-600 dark:text-warm-400",
                "Static snippets replay a fixed stream. For figures that react to user input, the figure code itself ",
                "compiles to wasm. With Therapy.jl the whole thing is one ",
                Code(:class => "text-accent-500 font-mono", "@island"),
                ":"
            ),
            Pre(:class => "bg-warm-900 dark:bg-warm-950 text-warm-200 p-6 rounded-lg overflow-x-auto border border-warm-800",
                Code(:class => "language-julia text-sm font-mono",
                    """# host app setup — once
Therapy.register_canvas_provider!(name = "WasmMakie",
    import_specs = WasmMakie.import_specs,
    js_glue      = WasmMakie.js_glue)

@island function LivePlot()
    freq, set_freq = create_signal(Int64(3))
    create_effect(() -> begin
        fig = WM.Figure(size = (600.0, 300.0))
        ax  = WM.Axis(fig[1, 1]; title = "live")
        # ... build the figure from freq() ...
        WM.render!(fig, WM.WasmCtx())   # draws to the island's <canvas>
    end)
    Div(Canvas(:width => 600, :height => 300),
        Button(:on_click => () -> set_freq(freq() + Int64(1)), "+"))
end""")
            ),
            P(:class => "text-warm-600 dark:text-warm-400",
                "The ", A(:href => "/WasmMakie.jl/gallery/", :class => "text-accent-500 hover:text-accent-600 underline", "Gallery"),
                " page opens with exactly this pattern running live. Hosts other than Therapy use the same two ",
                "functions through the generic contract — see ",
                A(:href => "/WasmMakie.jl/embedding/", :class => "text-accent-500 hover:text-accent-600 underline", "Embedding"), "."
            )
        )
    )
end

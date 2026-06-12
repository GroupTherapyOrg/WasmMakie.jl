() -> begin
    Div(:class => "space-y-10 max-w-3xl",
        H1(:class => "text-3xl font-serif font-bold text-warm-900 dark:text-warm-100", "Embedding"),
        P(:class => "text-warm-600 dark:text-warm-400",
            "WasmMakie is host-agnostic: it knows nothing about Therapy, Pluto, or any framework. ",
            "Hosts integrate through a small embedding contract — every plot on this site uses it."
        ),

        Div(:class => "space-y-4",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "Static snippets"),
            P(:class => "text-warm-600 dark:text-warm-400",
                Code(:class => "text-accent-500 font-mono", "html_snippet(fig; fonts = true)"),
                " returns a self-contained HTML fragment: a ",
                Code(:class => "text-accent-500 font-mono", "<canvas>"),
                ", the figure's recorded Canvas2D command stream, and the replayer. ",
                "Drop it into any page — static site generators, notebooks, emails to your collaborators. ",
                "Set ", Code(:class => "text-accent-500 font-mono", "fonts = false"),
                " on all but the first snippet per page: the bundled Makie fonts (~1.9 MB) register document-wide once."
            ),
            Pre(:class => "bg-warm-900 dark:bg-warm-950 text-warm-200 p-6 rounded-lg overflow-x-auto border border-warm-800",
                Code(:class => "language-julia text-sm font-mono",
                    """first  = WM.html_snippet(fig1)                # embeds fonts
second = WM.html_snippet(fig2; fonts = false)  # reuses them""")
            )
        ),

        Div(:class => "space-y-4",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "Wasm modules"),
            P(:class => "text-warm-600 dark:text-warm-400",
                "For reactive figures the host compiles figure-building code with WasmTarget against WasmMakie's ",
                "canvas2d import surface, then instantiates it over a canvas:"
            ),
            Ul(:class => "list-disc pl-6 space-y-2 text-warm-600 dark:text-warm-400",
                Li(Code(:class => "text-accent-500 font-mono", "import_specs()"),
                   " — the canvas2d import declarations WasmTarget compiles against"),
                Li(Code(:class => "text-accent-500 font-mono", "js_glue()"),
                   " — the JS implementations of those imports (the actual Canvas2D calls), exposed as ",
                   Code(:class => "text-accent-500 font-mono", "canvas2d_imports"), " / ",
                   Code(:class => "text-accent-500 font-mono", "window.__tw_canvas_glue")),
                Li(Code(:class => "text-accent-500 font-mono", "font_faces_json()"),
                   " — the bundled FontFaces for ", Code(:class => "text-accent-500 font-mono", "canvas2d_load_fonts")),
                Li(Code(:class => "text-accent-500 font-mono", "wasm_html_snippet(bytes, export_name; width, height)"),
                   " — a one-call self-contained fragment around a host-compiled module")
            ),
            P(:class => "text-warm-600 dark:text-warm-400",
                "Inside the compiled code, ",
                Code(:class => "text-accent-500 font-mono", "render!(fig, WasmCtx())"),
                " emits draw calls through the imports; on the host the same figure renders through ",
                Code(:class => "text-accent-500 font-mono", "RecordingCtx()"),
                " — the two streams are bit-identical (the differential corpus gates this)."
            )
        ),

        Div(:class => "space-y-4",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "Existing hosts"),
            Ul(:class => "list-disc pl-6 space-y-2 text-warm-600 dark:text-warm-400",
                Li(Code(:class => "text-accent-500 font-mono", "Therapy.jl"),
                   " — register WasmMakie as the canvas provider and write ",
                   Code(:class => "text-accent-500 font-mono", "@island"),
                   " functions (the pattern in ",
                   A(:href => "/WasmMakie.jl/getting-started/", :class => "text-accent-500 hover:text-accent-600 underline", "Getting Started"),
                   ")"),
                Li(Code(:class => "text-accent-500 font-mono", "PlutoIslands.jl"),
                   " — published notebooks whose WasmMakie figure cells stay reactive serverlessly"),
                Li("Anything else — the contract is five functions and a canvas; no framework required")
            )
        ),

        Div(:class => "space-y-4",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "CanvasMakie (server-side twin)"),
            P(:class => "text-warm-600 dark:text-warm-400",
                "The same repo ships CanvasMakie, a true Makie backend over the identical draw layer: ",
                Code(:class => "text-accent-500 font-mono", "CanvasMakie.activate!()"),
                " then ordinary Makie code produces PNGs through ",
                Code(:class => "text-accent-500 font-mono", "colorbuffer"), " / ",
                Code(:class => "text-accent-500 font-mono", "backend_show"),
                ". It passes 149/166 (89.8%) of Makie's 2D reference tests — the ",
                A(:href => "https://github.com/GroupTherapyOrg/WasmMakie.jl/blob/main/CanvasMakie/CONFORMANCE.md",
                  :target => "_blank", :class => "text-accent-500 hover:text-accent-600 underline", "conformance audit"),
                " has the full interface table and scores."
            )
        )
    )
end

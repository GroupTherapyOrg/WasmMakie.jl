() -> begin
    Div(:class => "space-y-12",
        Div(:class => "space-y-4",
            H1(:class => "text-3xl font-serif font-bold text-warm-900 dark:text-warm-100", "Gallery"),
            P(:class => "text-warm-600 dark:text-warm-400 max-w-3xl",
                "Every figure below is the release-gating core corpus rendered by WasmMakie itself at build time: ",
                "a recorded Canvas2D command stream replayed in your browser by the bundled renderer. ",
                "No screenshots. The corpus is a ratchet — scenes are only ever added, and each must stay within ",
                "scored distance of real Makie output (",
                A(:href => "https://github.com/GroupTherapyOrg/WasmMakie.jl/blob/main/reftests/scores_core_corpus.tsv",
                  :target => "_blank", :class => "text-accent-500 hover:text-accent-600 underline", "the ledger"),
                ")."
            )
        ),
        # Live wasm island — the interactive counterpart of the static grid
        Div(:class => "space-y-4",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "Live: compiled to wasm"),
            P(:class => "text-warm-600 dark:text-warm-400 max-w-3xl",
                "The dashboard below is the other half of the story: one WasmMakie figure with a 2×2 grid of Axes, ",
                "compiled to WebAssembly at build time. The buttons drive reactive signals — every change re-runs the ",
                "figure inside wasm and redraws in ~2 ms. No server is involved; this page is static files."
            ),
            LiveDashboard()
        ),
        Div(:class => "space-y-4",
            H2(:class => "text-2xl font-serif font-semibold text-warm-900 dark:text-warm-100", "The core corpus"),
            GalleryGrid()
        )
    )
end

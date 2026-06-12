# ── GalleryGrid (WASMMAKIE U-004) ──
# The ENTIRE core-corpus (the ratchet that gates releases) rendered at build
# time through the embedding contract: html_snippet(fig) = <canvas> + the
# recorded Canvas2D command stream + the bundled replayer. What you see on
# the gallery page is exactly what ships to any host — no screenshots.
#
# Fonts: the FIRST snippet embeds the bundled Makie FontFaces (registered
# document-wide); the rest reuse them with fonts=false.
import WasmMakie as WM
using Therapy: RawHtml

include(normpath(joinpath(@__DIR__, "..", "..", "..", "reftests", "core_corpus.jl")))

const GALLERY_W = 400.0
const GALLERY_H = 300.0

function GalleryGrid()
    first_snippet = true
    cells = map(CoreCorpus.CORPUS) do scene
        fig = WM.Figure(size = (GALLERY_W, GALLERY_H))
        scene.build_core(fig)
        snippet = WM.html_snippet(fig; fonts = first_snippet)
        first_snippet = false
        name = replace(scene.name, r"^(core|recipes): " => "")
        Div(
            :class => "rounded-lg border border-warm-200 dark:border-warm-800 overflow-hidden bg-white",
            Div(:class => "px-3 pt-2",
                Span(:class => "text-sm font-semibold text-warm-800", name)),
            Div(:class => "p-1 gallery-canvas", RawHtml(snippet)),
        )
    end
    Div(:class => "grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4", cells...)
end

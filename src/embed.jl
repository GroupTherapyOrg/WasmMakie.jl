# The embedding contract (E-001) — everything a host needs to show WasmMakie
# figures, with NO host-specific code in this package (P1):
#
#   import_specs()        — the canvas2d wasm import surface   (ops.jl)
#   js_glue()             — the canonical JS import factory + font loader
#   js_specs()            — op signature table for the replayer
#   font_faces_json()     — self-contained FontFace payload     (fonts.jl)
#   replay_js()           — the command-stream replayer source
#   html_snippet(fig)     — SELF-CONTAINED static fragment: canvas + glue +
#                           fonts + recorded command stream + replay
#   wasm_html_snippet(bytes, export) — the same fragment around a
#                           HOST-COMPILED wasm module (stateless-recompute
#                           islands; WasmMakie does not compile — hosts own
#                           WasmTarget)
#   Base.show(text/html)  — Figures display inline anywhere HTML MIME works
#
# The acid test (README + suite): one plain HTML file, no framework, shows
# the plot in a browser.

const _EMBED_COUNTER = Ref(0)

"The bundled command-stream replayer (assets/replay.js) source."
replay_js() = read(joinpath(dirname(@__DIR__), "assets", "replay.js"), String)

function _next_embed_id()
    _EMBED_COUNTER[] += 1
    return "wasmmakie-$(_EMBED_COUNTER[])"
end

"""
    html_snippet(fig::Figure; id = <auto>, fonts = true) -> String

A fully self-contained HTML fragment displaying the figure: canvas element,
generated glue, bundled fonts (data: URLs), the recorded command stream, and
the replayer. No external requests, no framework, no wasm — the figure is
already computed. For interactive islands use `wasm_html_snippet` with a
host-compiled module.
"""
function html_snippet(fig::Figure; id::AbstractString = _next_embed_id(),
                      fonts::Bool = true)
    r = RecordingCtx()
    render!(fig, r)
    w = Int64(round(fig.width))
    h = Int64(round(fig.height))
    faces = fonts ? font_faces_json() : "[]"
    return """
    <div class="wasmmakie-figure">
    <canvas id="$(id)" width="$(w)" height="$(h)"></canvas>
    <script>
    (function () {
    $(js_glue())
    $(replay_js())
    const __canvas = document.getElementById("$(id)");
    var __draw = function () {
      replayCommands($(to_json(r)), __canvas, canvas2d_imports, $(js_specs()));
      __canvas.dataset.wasmmakieDone = "1";   // hosts/tests can await this
    };
    // fonts must never block drawing (text falls back to the family stack)
    try { canvas2d_load_fonts($(faces)).then(__draw, __draw); } catch (e) { __draw(); }
    })();
    </script>
    </div>
    """
end

"""
    wasm_html_snippet(wasm_bytes, export_name; width, height, id, fonts) -> String

The same self-contained fragment around a HOST-COMPILED wasm module: the
canvas, glue, fonts, the module (base64), instantiation against the
`canvas2d` imports, and one call of `export_name` (the stateless-recompute
entry). Hosts that re-render on state changes keep the instance and call the
export again.
"""
function wasm_html_snippet(wasm_bytes::Vector{UInt8}, export_name::AbstractString;
                           width::Integer, height::Integer,
                           id::AbstractString = _next_embed_id(),
                           fonts::Bool = true)
    b64 = _base64encode(wasm_bytes)
    faces = fonts ? font_faces_json() : "[]"
    return """
    <div class="wasmmakie-figure">
    <canvas id="$(id)" width="$(Int(width))" height="$(Int(height))"></canvas>
    <script>
    (function () {
    $(js_glue())
    const __canvas = document.getElementById("$(id)");
    const __bytes = Uint8Array.from(atob("$(b64)"), function (c) { return c.charCodeAt(0); });
    var __fonts = (function () {
      try { return canvas2d_load_fonts($(faces)).catch(function () {}); }
      catch (e) { return Promise.resolve(); }
    })();
    __fonts.then(function () {
      return WebAssembly.instantiate(__bytes, {
        canvas2d: canvas2d_imports(__canvas),
        Math: { pow: Math.pow },
        io: new Proxy({}, { get: function () { return function () {}; } }),
      }, { builtins: ["js-string"] });
    }).then(function (mod) {
      __canvas.wasmmakie = mod.instance;
      mod.instance.exports["$(export_name)"]();
      __canvas.dataset.wasmmakieDone = "1";   // hosts/tests can await this
    });
    })();
    </script>
    </div>
    """
end

"Figures display inline wherever the HTML MIME is honored (notebooks, docs)."
Base.show(io::IO, ::MIME"text/html", fig::Figure) = print(io, html_snippet(fig))

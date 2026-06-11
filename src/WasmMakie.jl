"""
    WasmMakie

Makie's plotting API rendered through HTML Canvas2D, designed to compile to
WebAssembly via WasmTarget.jl.

WasmMakie is a standalone, host-agnostic package — like a normal Makie backend.
It has no knowledge of any web framework or notebook system. Hosts integrate
against a small generic embedding contract:

  - `import_specs()` — the Canvas2D import surface (generated from the ops table)
  - `js_glue()`      — the canonical JS import-object factory (same table)
  - any function that builds a `Figure` and calls `render!(fig, ctx)` is
    guaranteed WasmTarget-compilable
  - `show(io, MIME"text/html", fig)` — a fully self-contained canvas + wasm
    HTML fragment

The acid test: a plain HTML file with a `<canvas>`, the compiled wasm module,
and the glue JS shows a plot — no framework anywhere.

Architecture: two tracks, one draw layer. The `draw/` layer consists of pure
functions `(plain data, ctx) → canvas ops`, where `ctx` is either a `WasmCtx`
(wasm import stubs, compiled by WasmTarget) or a `RecordingCtx` (typed command
vector, host-side). The `CanvasMakie/` subpackage is a true `Makie.MakieScreen`
backend driving the same draw layer from real Makie — the translation oracle
and the upstream candidate.

The closed-world type discipline for everything under `src/core/` and
`src/draw/` is documented in the plan; the short version: concrete typed
structs only — no `Dict{Symbol,Any}`, no `Any`/`Function` fields, no
abstract-element vectors, no ccall, no IO in compiled paths.
"""
module WasmMakie

# Stories land in this order (see WASMMAKIE_PLAN.md):
#   ops.jl   — the canvas ops table (F-002) ✓
#   ctx.jl   — WasmCtx / RecordingCtx (F-003)
#   draw/    — shared draw layer (M1)
#   core/    — static typed Makie API (M2)
#   vendor/  — vendored leaf algorithms (M2)
#   embed.jl — embedding contract (M7)

include("ops.jl")
include("ctx.jl")
include("draw/lines.jl")
include("draw/scatter.jl")
include("draw/image.jl")
include("draw/poly.jl")

export CANVAS_OPS, import_specs, js_glue
export AbstractCtx, WasmCtx, RecordingCtx, Command, to_json

end # module

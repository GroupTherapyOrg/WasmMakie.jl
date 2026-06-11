# WasmMakie.jl

**Makie's plotting API, rendered through HTML Canvas2D, compiled to WebAssembly.**

WasmMakie gives you Makie's exact user-facing API — `Figure`, `Axis`, `lines!`, `scatter!`,
`heatmap!`, themes, layouts — with all plotting logic (tick finding, layout solving, color
mapping, text layout, rendering) running as a WasmGC module in the browser, compiled from
Julia by [WasmTarget.jl](https://github.com/GroupTherapyOrg/WasmTarget.jl). No Julia server,
no precomputed state.

## The acid test

A plain HTML file with a `<canvas>`, the compiled wasm module, and the glue JS shows a plot.
No framework anywhere. That is the standing definition of "self-contained" for this package —
any notebook system or web framework that can render `text/html` (or wire wasm imports) gets
working plots, but none of them are referenced by this package.

```julia
using WasmMakie

fig = Figure()
ax = Axis(fig[1, 1], title = "sine")
lines!(ax, 0..10, sin)
fig   # show(io, MIME"text/html", fig) → self-contained canvas + wasm fragment
```

## Architecture: two tracks, one draw layer

```
                 ┌────────────────────────────────────────────┐
                 │            src/draw/  (shared)             │
                 │  pure fns: (plain data, ctx) → canvas ops  │
                 └────────────▲───────────────▲───────────────┘
                              │               │
        ┌─────────────────────┴───┐       ┌───┴──────────────────────────┐
        │ CanvasMakie/  (Track A) │       │ src/core/  (Track B)         │
        │ true Makie.MakieScreen  │       │ static typed Makie API,      │
        │ backend on REAL Makie,  │       │ no reactive spine, compiled  │
        │ native Julia,           │       │ by WasmTarget; islands are   │
        │ RecordingCtx → replay   │       │ stateless recompute          │
        │ → headless-browser PNG  │       │ WasmCtx → wasm imports       │
        └─────────────────────────┘       └──────────────────────────────┘
          the translation oracle            the wasm product
          + the upstream candidate
```

- **`ops.jl`** is the single source of truth for the Canvas2D surface: every op's Julia stub,
  wasm signature, and JS body live in one table; the import specs and the JS glue are generated
  from it. Hosts never hand-copy the import list.
- **Verification** is differential, in the WasmTarget tradition: CanvasMakie is scored against
  CairoMakie's reference images (Makie's own ~372-test suite, tile-max-RMSE); the wasm build is
  gated on **command-stream equality** with the host-side run of the same program — a
  pixel-flake-free oracle.
- **Vendored, not invented**: Makie's pure-Julia leaf algorithms (PlotUtils ticks, GridLayoutBase
  solver, colormaps, text layouting, the `jl_rasterizer` software rasterizer) are vendored
  verbatim with provenance headers — see [VENDORED.md](VENDORED.md). Divergences exist only for
  demonstrable target constraints and are marked `# WASM-DIVERGENCE:`.

## Status

Pre-alpha, under active construction. The build plan and story ledger live in the parent
workspace (`WASMMAKIE_PLAN.md`). Makie pin: 0.24.11 / CairoMakie 0.15.11.

## Packages

| package | what | depends on |
|---|---|---|
| `WasmMakie` (root) | wasm-compilable core + draw layer + embedding contract | stdlib only |
| `CanvasMakie/` | true Makie backend (host-side), reference-suite runner | Makie, WasmMakie |

## License

MIT. Vendored code is from MIT-licensed sources (Makie.jl and its ecosystem); see VENDORED.md.

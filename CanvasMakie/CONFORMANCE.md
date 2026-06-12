# CanvasMakie backend conformance (WASMMAKIE U-002)

CanvasMakie is a **static rasterizing backend** in the same class as
CairoMakie: it consumes Makie's computed plot graph and renders to an image
(via a recorded Canvas2D command stream replayed in Chromium). This audit
tracks it against the backend interface Makie's own backends implement.

## Backend interface

| Interface | Status | Notes |
|---|---|---|
| `Screen <: Makie.MakieScreen` | ✅ | `CanvasMakie.Screen` (screen.jl) |
| `Screen(scene; screen_config...)` | ✅ | `ScreenConfig(px_per_unit)` |
| `Makie.apply_screen_config!` | ✅ | re-applies px_per_unit |
| `Makie.colorbuffer(screen)` | ✅ | RecordingCtx → Chromium replay → PNG → matrix |
| `Makie.backend_show(::Screen, io, ::MIME"image/png", scene)` | ✅ | static export |
| `Makie.backend_showable` | ✅ | `image/png` |
| `Base.display(::Screen, scene)` | ✅ | renders + returns screen |
| `Base.size`, `Base.empty!`, `Base.delete!`, `Base.close`, `Base.isopen` | ✅ | stateless recorder — empty!/delete! are no-ops by design |
| `Makie.px_per_unit` | ✅ | from ScreenConfig |
| `activate!(; screen_config...)` + backend registration (`__init__`) | ✅ | `Makie.set_active_backend!` |
| Incremental `insertplots!` re-render | ➖ | every render records a fresh stream (valid for a static backend; CairoMakie likewise re-draws) |
| Event loop / interaction (`pick`, ticks, input events) | ❌ n/a | static backend class — same scope as CairoMakie (no pick support there either for most uses); interactivity ships through the WasmMakie wasm path instead |
| Video/Steps recording (`VideoStream`) | ❌ | stills only (the refsuite skips video tests for the same reason) |

### Atomic plot coverage (the draw side)

`draw_atomic` implementations: Lines, LineSegments, Scatter (incl. Char /
BezierPath / image-matrix markers), Text (FreeType outline → path fill),
Image, Heatmap, Mesh (2D, via the shared Gouraud rasterizer), Poly overrides
(paths + per-vertex mesh fallback), recipe recursion for non-atomic plot
trees. Loud errors (not silent wrong output) for: 3D mesh shading, pattern
fills. See `reftests/scores_*.tsv` for the per-test ledger.

## Cross-backend reference scores

Methodology mirrors Makie's ReferenceTests: render the upstream 2D test
files and score each image against the recorded reference set with the
vendored tile scorer (`reftests/scorer.jl`, threshold 0.05).

**Honest asymmetry**: the reference images ARE CairoMakie's recordings (the
official refimage artifact), so CairoMakie's score against them is identity
by construction. CanvasMakie's number measures distance to CairoMakie's
output — the same role GLMakie/WGLMakie's published cross-backend scores
play against the shared reference set.

| Backend | 2D reference pass rate | Notes |
|---|---|---|
| CairoMakie | reference (identity) | the recorded set |
| **CanvasMakie** | **149/166 (89.8%)** | short_tests 19/20 · primitives 25/30 · makielayout 21/23 · examples2d 84/93; 2D scope (3D/volume/video skipped, denominator excludes them) |

Remaining fails are antialiasing-engine deltas (dense thin geometry) and
two reference-artifact cases — the per-test breakdown with scores lives in
`reftests/scores_*.tsv` (a ratchet: numbers may only improve).

Additional parity gates (beyond the reference suite):

| Gate | Result |
|---|---|
| wasm ↔ host command streams (diffpass) | 14/14 bit-identical |
| static core vs real Makie (corpus, 0.30 tier) | 32/32 |
| Budgets | ~189 KB gzip module · ~1.8 ms median redraw |

Regenerate: `julia +1.12 --project=CanvasMakie/test reftests/run_refsuite.jl
short_tests primitives figures_and_makielayout examples2d`.

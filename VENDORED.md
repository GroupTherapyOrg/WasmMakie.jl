# Vendored code provenance ledger

Every file under `src/vendor/` (and every translated `src/draw/` file) is copied from an
MIT-licensed reference source, verbatim where possible. Divergences exist only for demonstrable
target constraints (no ccall, closed-world types) and are marked inline with `# WASM-DIVERGENCE:`.

## Pinned reference versions

| package | version | local source |
|---|---|---|
| Makie | 0.24.11 | `~/.julia/packages/Makie/WKgwk` |
| CairoMakie | 0.15.11 | `~/.julia/packages/CairoMakie/9K2tG` |
| PlotUtils | 1.4.4 | `~/.julia/packages/PlotUtils/HX80C` |
| GridLayoutBase | 0.9.2 | `~/.julia/packages/GridLayoutBase/kiave` |
| GeometryBasics | 0.5.10 | `~/.julia/packages/GeometryBasics/yB1f1` |
| ColorSchemes | — | `~/.julia/packages/ColorSchemes/3BWhh` |
| Showoff | — | `~/.julia/packages/Showoff/ZtTt9` |

Re-pinning is a deliberate act — the full policy below (plan story U-005).

## Re-pinning policy (U-005)

Tracking Makie is a **batch, reviewed operation** — never a drive-by version bump. One
re-pin = one PR that moves EVERY pinned package together to a mutually consistent set
(Makie + CairoMakie + GridLayoutBase + PlotUtils + GeometryBasics resolve together; mixed
pins are how silent layout drift happens).

**When to re-pin**
- A Makie minor release lands that U-003 upstreaming needs, or that fixes/changes
  rendering behavior our corpora encode.
- Security/correctness fixes in any pinned package.
- NOT for every patch release — the pin buys deterministic parity; churn costs a full
  re-review.

**ComputePipeline watch (standing item)**: Makie is migrating attribute computation to
ComputePipeline (the `attr[:positions_transformed_f32c]`-style computed-graph reads our
CanvasMakie adapters depend on; 0.24 began it, 0.25 expands it). When a re-pin crosses a
ComputePipeline version bump, re-vendor the CanvasMakie adapters WHOLESALE from the
matching CairoMakie tag rather than patching — the attribute access patterns are
backend-contract surface, and CairoMakie's same-version source is the only ground truth
(per the copy-from-reference rule: verbatim first, diverge only for target constraints).

**Process (in order)**
1. Resolve the new version set in `CanvasMakie/test` (the host-oracle env) and record the
   new depot slugs in the table above.
2. For every ledger row below: `diff` the OLD depot copy against the NEW one for the
   source path, then port the upstream delta into our copy — preserving every
   `# WASM-DIVERGENCE:` marker and the verbatim-translation structure. A row with no
   upstream diff is untouched. Update the row's version reference.
3. Regenerate generated vendors: `reftests/gen_font_metrics.jl` (if fonts or
   FreeTypeAbstraction changed), the viridis table (if colorsampler changed).
4. Bump the reference images: replace `reftests/reference_images/reference_images.tar`
   with the recorded refimages for the NEW Makie tag (Makie ReferenceTests release
   artifacts), re-extract, and re-score.
5. Re-run ALL gates, ratchet rule in force (each metric must hold or improve, else the
   re-pin is blocked until the regression is understood):
   - `julia +1.12 --project=test test/runtests.jl` (suite incl. C-002 subprocess oracle,
     W-002/W-005 wasm diffpass 14/14 EQUAL)
   - `julia +1.12 --project=CanvasMakie/test reftests/run_core_corpus.jl` (32/32)
   - `reftests/run_refsuite.jl short_tests primitives figures_and_makielayout examples2d`
     (host_refpass ≥ current %)
   - `reftests/run_budgets.jl` (size/compile/redraw budgets)
6. Single conventional commit: `feat: re-pin Makie <old> → <new> (re-vendor batch)` with
   the per-row delta summary in the body; CHANGELOG entry lands via release-please.

## Ledger

Required header in every vendored/translated file:

```julia
# VENDORED from <Package> v<version> — <path within package>
# License: MIT (see VENDORED.md). Divergences marked WASM-DIVERGENCE.
```

| file here | source | kind |
|---|---|---|
| `reftests/scorer.jl` | Makie.jl master `ReferenceTests/src/compare_media.jl` (compare_images verbatim; loading/dir-scoring adapted — stills only, PNGFiles) | tooling |
| `src/draw/lines.jl` | CairoMakie v0.15.11 `src/lines.jl` (draw_single_lines/draw_single_segments/draw_lineplot single-color branch) + `src/utils.jl` (to_cairo_linestyle/linecap/joinstyle) — Cairo→Canvas2D; explicit begin_path per run (canvas stroke keeps paths); draw_multi NOT yet translated | draw layer |
| `CanvasMakie/src/lines.jl` | CairoMakie v0.15.11 `src/lines.jl` (draw_atomic extraction + add_projected_line_points! clipspace stage) — clip planes NOT yet applied | adapter |
| `src/draw/image.jl` | CairoMakie v0.15.11 `src/image-hmap.jl` (draw_image fast path, _draw_rect_heatmap incl. AA-seam padding) — blit via buffered-image protocol, negative-h flip ≙ negative Cairo scale | draw layer |
| `CanvasMakie/src/image.jl` | CairoMakie v0.15.11 `src/image-hmap.jl` (image_grid!, regularly_spaced_array_to_range verbatim, fast-path conditions) — clip planes + non-default uv_transform not consumed | adapter |
| `CanvasMakie/src/scatter.jl` | CairoMakie v0.15.11 `src/scatter.jl` (project_marker/project_flipped/size_model! verbatim; draw_atomic extraction) — clip planes not applied | adapter |
| `src/draw/scatter.jl` | CairoMakie v0.15.11 `src/scatter.jl` (draw_marker Circle/Rect/BezierPath, draw_path/path_command) — stroke-after-restore calibrated against oracle output | draw layer |
| `src/draw/poly.jl` | CairoMakie v0.15.11 `src/overrides.jl` (draw_poly path building, polypath even-odd interiors) | draw layer |
| `CanvasMakie/src/poly.jl` | CairoMakie v0.15.11 `src/overrides.jl` (draw_plot(Poly) hasmethod dispatch, draw_poly methods for points/lists/Rect2/Circle/Polygon) + `src/utils.jl` (cairo_viewport_matrix/build_combined_transformation_matrix verbatim) — clip planes, patterns, BezierPath shapes, mesh fallback deferred | adapter |
| `CanvasMakie/src/screen.jl` (walk) | CairoMakie v0.15.11 `src/plot-primitives.jl` (cairo_draw walk, prepare_for_scene, check_parent_plots) — rasterize path dropped (image-only) | adapter |
| `CanvasMakie/src/text.jl` | CairoMakie v0.15.11 `src/scatter.jl` draw_text (per-glyph extraction loop) — RENDERING diverges by design: FreeType outline decomposition → encoded paths instead of cairo_show_glyphs; batching dropped; glow loud | adapter |
| `src/vendor/ticks.jl` | PlotUtils v1.4.4 `src/ticks.jl` (optimize_ticks/optimize_ticks_typed/bounding_order_of_magnitude/postdecimal_digits/fallback_ticks; orig. Gadfly, Daniel Jones) — Dict→if-chain log bases, @warn stripped, Date methods dropped, @constprop :none (1.12 inference recursion) | vendor |
| `src/vendor/tick_format.jl` | Makie v0.24.11 `src/tick_format.jl` (Showoff-subset on Base.Ryu) — TickLabel struct replaces RichText for scientific labels; Ryu writefixed/writeexp need WT overlays (W-004) | vendor |
| `src/vendor/colors.jl` + `colormap_viridis.jl` | Makie v0.24.11 `src/colorsampler.jl` (interpolated_getindex) + generated 256-entry viridis table from to_colormap(:viridis) — Float64 lerp (≤1e-7 vs Makie Float32, pixel-irrelevant) | vendor |
| `src/core/layout.jl` | GridLayoutBase v0.9.2 `src/gridlayout.jl` (compute_rowcols + compute_col_row_sizes solver math, translated subset: Inside/Outside, Fixed/Relative/Auto, protrusion negotiation, center alignment) — Observable protocol replaced by plain args | vendor |
| `src/vendor/linear_ticks.jl` | Makie v0.24.11 `src/makielayout/ticklocators/linear.jl` (locateticks + scale_range/_staircase/EdgeInteger — the `automatic` tick path, Matplotlib MaxNLocator port) verbatim | vendor |
| `assets/fonts/` | Makie v0.24.11 `assets/fonts/` (TeXGyreHerosMakie Regular/Bold/Italic/BoldItalic + DejaVuSans + LICENSES.md, byte-identical copies; GUST Font License / Bitstream Vera license) — loaded via FontFace by `canvas2d_load_fonts` so every host draws text with identical fonts (T-001) | vendor |
| `src/vendor/text_layouting.jl` | Makie v0.24.11 `src/layouting/text_layouting.jl` (glyph_collection: x accumulation, word wrap, \n splitting, justification, h/v align, rotation about anchor — structure preserved line-for-line) — typed translation: ExtentProvider (canvas measureText) replaces FreeTypeAbstraction; views→index ranges; Float32→Float64; one font/scale per run; color attrs dropped | vendor |
| `src/vendor/font_metrics.jl` | GENERATED from bundled fonts via FreeTypeAbstraction (reftests/gen_font_metrics.jl) — per-em glyph metrics ×5 faces ×97 cps (ASCII + − ×) + face-level ascender/descender/height; mirrors Makie GlyphExtent(font,char) field-for-field | vendor |
| `src/vendor/contour.jl` | Contour.jl v0.6 `src/Contour.jl` + `interpolate.jl` (marching squares: classification, ambiguous bilinear disambiguation, chase/trace with loopback) — Dict cell store → dense UInt8 cell array (P5: no Dict; faster); flat z + dims; tuple-LUT → if-chains | vendor |
| `src/draw/mesh.jl` | Makie v0.24.11 `src/jl_rasterizer/main.jl` (edge functions, bbox scan, barycentric w/area, depth ≤, standard_transparency blend) — shader machinery (@nospecialize Functions) dropped for the one needed program (Gouraud vertex color); Colorant buffers → flat NTuple RGBA; winding-agnostic | vendor |

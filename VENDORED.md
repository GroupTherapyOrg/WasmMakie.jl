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

Re-pinning is a deliberate act (plan story U-005): re-vendor with diff review, bump the
reference-image tarball, re-run all parity suites.

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

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

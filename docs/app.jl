#!/usr/bin/env julia
# WasmMakie.jl Documentation Site
#
# Usage (from WasmMakie.jl root directory):
#   julia --project=docs docs/app.jl dev    # Development server with HMR
#   julia --project=docs docs/app.jl build  # Build static site to docs/dist
#
# Dogfooding (U-004): every plot on this site is rendered BY WasmMakie —
# the gallery through the embedding contract (html_snippet: recorded
# command stream + bundled replayer), the live dashboard as a Therapy
# @island compiled to wasm through the generic canvas provider.

if !haskey(ENV, "JULIA_PROJECT")
    using Pkg
    Pkg.activate(@__DIR__)
end

using Therapy
using WasmMakie

# Islands on this site draw through WasmMakie's canvas2d import surface —
# the same generic provider contract any host uses (Therapy E-002).
Therapy.register_canvas_provider!(name = "WasmMakie",
    import_specs = WasmMakie.import_specs, js_glue = WasmMakie.js_glue)

cd(@__DIR__)

app = App(
    routes_dir = "src/routes",
    components_dir = "src/components",
    title = "WasmMakie.jl",
    output_dir = "dist",
    base_path = "/WasmMakie.jl",
    layout = :Layout
)

Therapy.run(app)

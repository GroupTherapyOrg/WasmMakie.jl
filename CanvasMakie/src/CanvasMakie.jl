"""
    CanvasMakie

A true Makie backend that renders scenes through HTML Canvas2D commands.

CanvasMakie implements the standard backend contract (`Makie.MakieScreen`,
`backend_show`, `colorbuffer`, `apply_screen_config!`) against real Makie core
running in native Julia. Scenes are drawn through WasmMakie's shared `draw/`
layer into a `RecordingCtx` command stream, then rasterized by replaying that
stream on a real canvas in headless Chromium — the exact JS path a live wasm
module uses in production.

This subpackage is both the translation oracle for the Cairo→Canvas2D port
(it runs Makie's reference-image test suite) and the upstream candidate for
MakieOrg. Usage matches any Makie backend:

    using CanvasMakie
    CanvasMakie.activate!()
"""
module CanvasMakie

using WasmMakie
using Makie
using Makie: Scene
import ColorTypes
import PNGFiles

include("render.jl")
include("screen.jl")
include("lines.jl")
include("scatter.jl")

export Screen

end # module

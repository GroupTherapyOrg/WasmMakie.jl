"""
    CanvasMakie

A true Makie backend that renders scenes to HTML Canvas2D commands.

CanvasMakie implements the standard backend contract (`Makie.MakieScreen`,
`backend_show`, `colorbuffer`, `apply_screen_config!`) against real Makie core
running in native Julia, and emits Canvas2D commands through WasmMakie's shared
`draw/` layer (via a `RecordingCtx`). Rendering to pixels happens by replaying
the command stream onto a real canvas in a headless browser.

This subpackage is both the translation oracle for the Cairo→Canvas2D port
(it runs Makie's reference-image test suite) and the upstream candidate for
MakieOrg.

The Makie dependency attaches with story D-001; until then this is a skeleton.
"""
module CanvasMakie

using WasmMakie

end # module

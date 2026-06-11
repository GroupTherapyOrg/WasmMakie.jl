# The Makie backend contract, mirrored from CairoMakie's screen.jl (MIT) —
# Screen type, constructors, apply_screen_config!, colorbuffer, backend_show.
# CanvasMakie is image-only (one render type: PNG via canvas), so the
# rendertype/surface machinery CairoMakie needs for SVG/PDF collapses away.

"""
    ScreenConfig(px_per_unit, visible)

Backend configuration. Constructed by `Makie.merge_screen_config` from theme
defaults (registered under `:CanvasMakie` in `__init__`) merged with
`activate!`/`Screen` keyword arguments.
"""
struct ScreenConfig
    px_per_unit::Float64
    visible::Bool
    function ScreenConfig(px_per_unit::Union{Nothing,Real}, visible::Union{Nothing,Bool})
        return new(isnothing(px_per_unit) ? 1.0 : Float64(px_per_unit),
                   isnothing(visible) ? true : visible)
    end
end

mutable struct Screen <: Makie.MakieScreen
    scene::Union{Nothing,Scene}
    config::ScreenConfig
end

function Base.show(io::IO, ::MIME"text/plain", screen::Screen)
    println(io, "CanvasMakie.Screen")
    println(io, "  size: $(size(screen))")
    print(io, "  px_per_unit: $(screen.config.px_per_unit)")
    return
end

Base.size(screen::Screen) = round.(Int, size(screen.scene) .* screen.config.px_per_unit)
Base.empty!(::Screen) = nothing  # nothing retained: every render records a fresh stream
Base.delete!(::Screen, ::Scene) = nothing
Base.delete!(::Screen, ::Scene, ::Makie.AbstractPlot) = nothing
Base.close(::Screen) = nothing
Base.isopen(::Screen) = true
Makie.px_per_unit(screen::Screen)::Float64 = screen.config.px_per_unit

function Screen(scene::Scene; screen_config...)
    config = Makie.merge_screen_config(ScreenConfig, Dict{Symbol,Any}(screen_config))
    return Screen(scene, config)
end
# io/path and storage-format constructors: image-only backend, one screen kind
Screen(scene::Scene, config::ScreenConfig, ::Union{Nothing,String,IO}, ::Union{MIME,Symbol}) =
    Screen(scene, config)
Screen(scene::Scene, config::ScreenConfig, ::Makie.ImageStorageFormat) = Screen(scene, config)

function Makie.apply_screen_config!(screen::Screen, config::ScreenConfig, scene::Scene, args...)
    screen.config = config
    screen.scene = scene
    return screen
end

Makie.backend_showable(::Type{Screen}, ::MIME"image/png") = true

function Makie.backend_show(screen::Screen, io::IO, ::MIME"image/png", scene::Scene)
    write(io, render_scene_png(screen))
    return screen
end

function Makie.colorbuffer(screen::Screen; figure = nothing)
    png = render_scene_png(screen)
    return PNGFiles.load(IOBuffer(png))
end

"""
    activate!(; screen_config...)

Make CanvasMakie the active Makie backend.
"""
function activate!(; screen_config...)
    Makie.set_screen_config!(CanvasMakie, screen_config)
    Makie.set_active_backend!(CanvasMakie)
    return
end

function __init__()
    # Register backend defaults so Makie.merge_screen_config finds them
    # (Makie ships entries only for its own known backends).
    for theme in (Makie.MAKIE_DEFAULT_THEME, Makie.CURRENT_DEFAULT_THEME)
        theme[:CanvasMakie] = Makie.Attributes(px_per_unit = 1.0, visible = true)
    end
    return
end

# ── scene drawing ────────────────────────────────────────────────────────
# Mirrors CairoMakie's plot-primitives.jl walk. D-001 scope: backgrounds and
# the z-sorted atomic-plot walk skeleton; draw_atomic methods land per plot
# type from D-002 on — an unimplemented atomic plot is a hard error, never a
# silent skip.

function render_scene_png(screen::Screen)
    scene = screen.scene
    w, h = size(screen)  # device pixels (scene px × px_per_unit)
    rctx = WasmMakie.RecordingCtx(; canvas_w = Float64(w), canvas_h = Float64(h))
    ppu = screen.config.px_per_unit
    WasmMakie.save(rctx)
    WasmMakie.scale_xy(rctx, ppu, ppu)
    draw_scene!(rctx, scene, Float64(size(scene)[2]))
    WasmMakie.restore(rctx)
    return commands_to_png(rctx, w, h)
end

function draw_scene!(rctx::WasmMakie.RecordingCtx, scene::Scene, root_h::Float64)
    draw_background!(rctx, scene, root_h)
    plots = Makie.collect_atomic_plots(scene)
    for p in plots
        draw_atomic(rctx, scene, p)
    end
    return
end

# Per-plot-type methods are added from D-002 on; anything unimplemented is loud.
draw_atomic(::WasmMakie.RecordingCtx, ::Scene, plot::Makie.AbstractPlot) =
    error("CanvasMakie: draw_atomic not implemented yet for $(typeof(plot).name.wrapper)")

function draw_background!(rctx::WasmMakie.RecordingCtx, scene::Scene, root_h::Float64)
    if scene.clear[]
        bg = Makie.to_color(scene.backgroundcolor[])
        vp = scene.viewport[]
        ox, oy = Float64.(Tuple(minimum(vp)))
        w, h = Float64.(Tuple(Makie.widths(vp)))
        # Makie scenes are y-up; canvas is y-down
        WasmMakie.set_fill_rgba(rctx,
            255.0 * Float64(ColorTypes.red(bg)), 255.0 * Float64(ColorTypes.green(bg)),
            255.0 * Float64(ColorTypes.blue(bg)), Float64(ColorTypes.alpha(bg)))
        WasmMakie.fill_rect(rctx, ox, root_h - (oy + h), w, h)
    end
    for child in scene.children
        draw_background!(rctx, child, root_h)
    end
    return
end

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

# Required by Makie's display machinery (display(fig), Stepper, record) —
# without this method the generic display recurses to a StackOverflow.
# Image backend: actual rendering happens in colorbuffer/backend_show
# (mirrors CairoMakie's non-interactive display).
function Base.display(screen::Screen, scene::Scene; connect = false, figure = nothing, screen_config...)
    Makie.push_screen!(scene, screen)
    return screen
end

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
# The walk is translated from CairoMakie's plot-primitives.jl `cairo_draw`:
# collect plots with the backend's atomicity override (Poly stays whole),
# z-sort, honor visibility up the parent chain, and re-prepare (translate +
# viewport clip) whenever the parent scene changes. Unimplemented plot types
# are a hard error, never a silent skip.

function render_scene_png(screen::Screen)
    scene = screen.scene
    w, h = size(screen)  # device pixels (scene px × px_per_unit)
    rctx = WasmMakie.RecordingCtx(; canvas_w = Float64(w), canvas_h = Float64(h))
    ppu = screen.config.px_per_unit
    WasmMakie.save(rctx)
    WasmMakie.scale_xy(rctx, ppu, ppu)
    canvas_draw(rctx, scene)
    WasmMakie.restore(rctx)
    return commands_to_png(rctx, w, h)
end

"""
    is_canvasmakie_atomic_plot(plot)::Bool

Which plots the walk treats as units (mirrors `is_cairomakie_atomic_plot`):
atomics, plus Poly — drawn as paths instead of decomposing to mesh + lines.
"""
is_canvasmakie_atomic_plot(plot::Makie.Plot) = Makie.is_atomic_plot(plot)
is_canvasmakie_atomic_plot(::Makie.Poly) = true

# Translated from CairoMakie check_parent_plots: visibility up the chain.
function check_parent_plots(f, plot::Makie.Plot)
    if f(plot)
        return check_parent_plots(f, Makie.parent(plot))
    else
        return false
    end
end
check_parent_plots(f, scene::Scene) = true

# Translated from CairoMakie prepare_for_scene: translate into the scene's
# frame (y measured from the top — canvas is y-down) and clip to its viewport.
function prepare_for_scene!(rctx::WasmMakie.RecordingCtx, scene::Scene)
    root_area_height = Makie.widths(Makie.viewport(Makie.root(scene))[])[2]
    scene_area = Makie.viewport(scene)[]
    scene_height = Makie.widths(scene_area)[2]
    scene_x_origin, scene_y_origin = scene_area.origin
    top_offset = root_area_height - scene_height - scene_y_origin
    WasmMakie.translate(rctx, Float64(scene_x_origin), Float64(top_offset))
    WasmMakie.begin_path(rctx)
    WasmMakie.rect(rctx, 0.0, 0.0, Float64.(Makie.widths(scene_area))...)
    WasmMakie.clip_nonzero(rctx)
    return
end

# Translated from CairoMakie cairo_draw (rasterize path dropped — image-only).
function canvas_draw(rctx::WasmMakie.RecordingCtx, scene::Scene)
    WasmMakie.save(rctx)
    draw_background!(rctx, scene, Float64(size(scene)[2]))

    allplots = Makie.collect_atomic_plots(scene; is_atomic_plot = is_canvasmakie_atomic_plot)
    sort!(allplots; by = Makie.zvalue2d)

    last_scene = scene
    WasmMakie.save(rctx)
    for p in allplots
        check_parent_plots(p) do plot
            Makie.to_value(get(plot, :visible, true))
        end || continue
        pparent = Makie.parent_scene(p)::Scene
        pparent.visible[]::Bool || continue
        if pparent != last_scene
            WasmMakie.restore(rctx)
            WasmMakie.save(rctx)
            prepare_for_scene!(rctx, pparent)
            last_scene = pparent
        end
        WasmMakie.save(rctx)
        draw_plot(rctx, pparent, p)
        WasmMakie.restore(rctx)
    end
    WasmMakie.restore(rctx)
    WasmMakie.restore(rctx)
    return
end

# Default: atomic plots dispatch to their draw_atomic; overrides (Poly) hook here.
draw_plot(rctx::WasmMakie.RecordingCtx, scene::Scene, plot::Makie.AbstractPlot) =
    draw_atomic(rctx, scene, plot)

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

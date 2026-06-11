# Poly overrides — translated from CairoMakie v0.15.11 src/overrides.jl (MIT):
# polys draw as paths instead of decomposing to mesh + lines. The hasmethod
# dispatch dance on raw args vs converted args is upstream's mechanism for
# catching recipe output.
#
# WASM-DIVERGENCE (recorded in the plan):
#  - clip planes / clip_poly not applied (consistent with D-002…D-004)
#  - Makie.AbstractPattern fills (hatching) and mesh fallback are loud errors
#    until R-005; BezierPath poly shapes likewise.

deref(x) = x
deref(x::Base.RefValue) = x[]

function draw_plot(rctx::WasmMakie.RecordingCtx, scene::Scene, poly::Makie.Poly)
    if Base.hasmethod(draw_poly, Tuple{WasmMakie.RecordingCtx, Scene, typeof(poly), typeof.(deref(poly.args[]))...})
        return draw_poly(rctx, scene, poly, deref(poly.args[])...)
    elseif Base.hasmethod(draw_poly, Tuple{WasmMakie.RecordingCtx, Scene, typeof(poly), typeof.(deref(poly.converted[]))...})
        return draw_poly(rctx, scene, poly, deref(poly.converted[])...)
    else
        # upstream worst case (overrides.jl draw_poly_as_mesh): draw the
        # poly's children — mesh (R-006 rasterizer path) + outline lines
        return draw_poly_as_mesh(rctx, scene, poly)
    end
end

function draw_poly_as_mesh(rctx::WasmMakie.RecordingCtx, scene::Scene, poly)
    for i in eachindex(poly.plots)
        draw_plot(rctx, scene, poly.plots[i])
    end
    return nothing
end

# ── projection: translated from CairoMakie utils.jl (viewport matrix path) ──
function _viewport_matrix(res)
    px_scale = Makie.Vec3d(0.5 * res[1], -0.5 * res[2], 1)
    px_offset = Makie.Vec3d(0.5 * res[1], 0.5 * res[2], 0)
    return Makie.transformationmatrix(px_offset, px_scale)
end

function _combined_transform_matrix(scene::Scene, space::Symbol, model::Makie.Mat4)
    f32convert = Makie.f32_convert_matrix(scene.float32convert, space)
    M = Makie.get_space_to_space_matrix(scene, space, :clip) * f32convert * model
    return _viewport_matrix(scene.camera.resolution[]) * M
end

function _project_poly_points(scene::Scene, poly, space::Symbol, points, model::Makie.Mat4)
    pts = Makie.apply_transform(Makie.transform_func(poly), points)
    T = _combined_transform_matrix(scene, space, model)
    return map(pts) do p
        p4 = T * Makie.to_ndim(Makie.Vec4d, Makie.to_ndim(Makie.Vec3d, p, 0.0), 1.0)
        w = Float64(p4[4])
        (Float64(p4[1]) / w, Float64(p4[2]) / w)
    end::Vector{NTuple{2,Float64}}
end

# ── color/style extraction ──────────────────────────────────────────────
# Translated from CairoMakie to_cairo_color (utils.jl): numbers AND color
# vectors route through assemble_colors (lowclip/highclip/nan_color aware);
# everything else picks up the plot's alpha. Patterns are loud until R-005.
function _poly_color(color, poly)
    color isa Makie.AbstractPattern &&
        error("CanvasMakie: pattern fills on poly not implemented yet (plan R-005)")
    if color isa Union{AbstractVector, Number}
        cmap = Makie.assemble_colors(color, Makie.Observable(color), poly)
        return Makie.to_color(Makie.to_value(cmap))
    end
    return Makie.to_color((color, Makie.to_value(poly.alpha)))
end

function _poly_style(poly)
    strokestyle = Makie.convert_attribute(poly.linestyle[], Makie.Key{:linestyle}())
    miter_limit = 2.0 * Makie.miter_angle_to_distance(Float64(poly.miter_limit[]))
    joinstyle = _cap_int(poly.joinstyle[], Makie.Key{:joinstyle}())
    linecap = _cap_int(poly.linecap[], Makie.Key{:linecap}())
    return strokestyle, miter_limit, joinstyle, linecap
end

_dash_pattern(::Nothing, _) = WasmMakie.NO_DASH
_dash_pattern(style::AbstractVector, sw) = WasmMakie.linestyle_to_pattern(Float64.(style), Float64(sw))

function _draw_poly_ring!(rctx, scene, poly, rings::Vector{Vector{NTuple{2,Float64}}},
                          color, strokecolor, strokewidth, strokestyle,
                          miter_limit, joinstyle, linecap)
    fr, fg, fb, fa = _rgba4(Makie.to_color(color))
    sr, sg, sb, sa = _rgba4(Makie.to_color(strokecolor))
    WasmMakie.draw_poly_rings!(rctx, rings, fr, fg, fb, fa, sr, sg, sb, sa,
                               Float64(strokewidth), _dash_pattern(strokestyle, strokewidth),
                               linecap, joinstyle, miter_limit)
    return
end

# ── draw_poly methods (translated, same argument shapes as upstream) ─────
function draw_poly(rctx::WasmMakie.RecordingCtx, scene::Scene, poly, points::Vector{<:Makie.Point2})
    strokestyle, miter_limit, joinstyle, linecap = _poly_style(poly)
    projected = _project_poly_points(scene, poly, poly.space[], points, poly.model[])
    return _draw_poly_ring!(rctx, scene, poly, [projected],
        _poly_color(poly.color[], poly), _poly_color(poly.strokecolor[], poly),
        poly.strokewidth[], strokestyle, miter_limit, joinstyle, linecap)
end

function draw_poly(rctx::WasmMakie.RecordingCtx, scene::Scene, poly, points_list::Vector{<:Vector{<:Makie.Point2}})
    strokestyle, miter_limit, joinstyle, linecap = _poly_style(poly)
    color = _poly_color(poly.color[], poly)
    strokecolor = _poly_color(poly.strokecolor[], poly)
    return Makie.broadcast_foreach(points_list, color, strokecolor, poly.strokewidth[]) do points, c, sc, sw
        projected = _project_poly_points(scene, poly, poly.space[], points, poly.model[])
        _draw_poly_ring!(rctx, scene, poly, [projected], c, sc, sw,
                         strokestyle, miter_limit, joinstyle, linecap)
    end
end

draw_poly(rctx::WasmMakie.RecordingCtx, scene::Scene, poly, circle::Makie.Circle) =
    draw_poly(rctx, scene, poly, Makie.GeometryBasics.decompose(Makie.Point2f, circle))

draw_poly(rctx::WasmMakie.RecordingCtx, scene::Scene, poly, mp::Makie.GeometryBasics.MultiPolygon) =
    draw_poly(rctx, scene, poly, mp.polygons)

draw_poly(rctx::WasmMakie.RecordingCtx, scene::Scene, poly, circles::Vector{<:Makie.Circle}) =
    draw_poly(rctx, scene, poly,
              [Makie.GeometryBasics.decompose(Makie.Point2f, c) for c in circles])

draw_poly(rctx::WasmMakie.RecordingCtx, scene::Scene, poly, rect::Makie.Rect2) =
    draw_poly(rctx, scene, poly, [rect])

function draw_poly(rctx::WasmMakie.RecordingCtx, scene::Scene, poly, rects::Vector{<:Makie.Rect2})
    strokestyle, miter_limit, joinstyle, linecap = _poly_style(poly)
    color = _poly_color(poly.color[], poly)
    strokecolor = _poly_color(poly.strokecolor[], poly)
    return Makie.broadcast_foreach(rects, color, strokecolor, poly.strokewidth[]) do rect, c, sc, sw
        # project the two corners (axis-aligned fast path, like create_shape_path!)
        corners = _project_poly_points(scene, poly, poly.space[], Makie.Point2d[
            Makie.Point2d(Makie.origin(rect)...),
            Makie.Point2d((Makie.origin(rect) .+ Makie.widths(rect))...),
        ], poly.model[])
        (x0, y0), (x1, y1) = corners
        fr, fg, fb, fa = _rgba4(Makie.to_color(c))
        sr, sg, sb, sa = _rgba4(Makie.to_color(sc))
        WasmMakie.draw_poly_rect!(rctx, min(x0, x1), min(y0, y1), abs(x1 - x0), abs(y1 - y0),
                                  fr, fg, fb, fa, sr, sg, sb, sa, Float64(sw),
                                  _dash_pattern(strokestyle, sw), linecap, joinstyle, miter_limit)
    end
end

function draw_poly(rctx::WasmMakie.RecordingCtx, scene::Scene, poly, polygon::Makie.GeometryBasics.Polygon)
    strokestyle, miter_limit, joinstyle, linecap = _poly_style(poly)
    ext = Makie.GeometryBasics.decompose(Makie.Point2f, polygon.exterior)
    rings = [_project_poly_points(scene, poly, poly.space[], ext, poly.model[])]
    for interior in polygon.interiors
        push!(rings, _project_poly_points(scene, poly, poly.space[],
              Makie.GeometryBasics.decompose(Makie.Point2f, interior), poly.model[]))
    end
    return _draw_poly_ring!(rctx, scene, poly, rings,
        _poly_color(poly.color[], poly), _poly_color(poly.strokecolor[], poly),
        poly.strokewidth[], strokestyle, miter_limit, joinstyle, linecap)
end

function draw_poly(rctx::WasmMakie.RecordingCtx, scene::Scene, poly,
                   polygons::Vector{<:Makie.GeometryBasics.Polygon})
    color = _poly_color(poly.color[], poly)
    strokecolor = _poly_color(poly.strokecolor[], poly)
    strokestyle, miter_limit, joinstyle, linecap = _poly_style(poly)
    return Makie.broadcast_foreach(polygons, color, strokecolor, poly.strokewidth[]) do polygon, c, sc, sw
        ext = Makie.GeometryBasics.decompose(Makie.Point2f, polygon.exterior)
        rings = [_project_poly_points(scene, poly, poly.space[], ext, poly.model[])]
        for interior in polygon.interiors
            push!(rings, _project_poly_points(scene, poly, poly.space[],
                  Makie.GeometryBasics.decompose(Makie.Point2f, interior), poly.model[]))
        end
        _draw_poly_ring!(rctx, scene, poly, rings, c, sc, sw,
                         strokestyle, miter_limit, joinstyle, linecap)
    end
end

# VENDORED (translated) from CairoMakie v0.15.11 — src/overrides.jl
# (draw_poly path building + polypath with interiors). License: MIT.
#
# Polygons arrive as projected scene-local pixel rings. Fill+stroke mirror
# the upstream order (fill_preserve → style → stroke); canvas keeps the path
# after fill so no preserve variant is needed. Stroke width here IS in the
# current user space (scene px), matching Cairo's poly stroking.

function _ring_path!(ctx, points::Vector{NTuple{2,Float64}})
    move_to(ctx, points[1][1], points[1][2])
    for k in 2:length(points)
        line_to(ctx, points[k][1], points[k][2])
    end
    close_path(ctx)
    return nothing
end

function _poly_stroke!(ctx, sr::Float64, sg::Float64, sb::Float64, sa::Float64,
                       strokewidth::Float64, pattern::Vector{Float64},
                       linecap::Int64, joinstyle::Int64, miter_limit::Float64)
    (strokewidth > 0.0 && sa > 0.0) || return nothing  # canvas ignores lineWidth=0
    set_line_style!(ctx, pattern, linecap, joinstyle, miter_limit)
    set_stroke_rgba(ctx, 255.0 * sr, 255.0 * sg, 255.0 * sb, sa)
    set_line_width(ctx, strokewidth)
    stroke(ctx)
    return nothing
end

"""
    draw_poly_rings!(ctx, rings, fill…, stroke…, …)

One polygon: first ring is the exterior, the rest are interior holes
(even-odd fill rule, translated from CairoMakie `polypath`). A single-ring
polygon is the plain `draw_poly(points)` case (nonzero fill).
"""
function draw_poly_rings!(ctx, rings::Vector{Vector{NTuple{2,Float64}}},
                          fr::Float64, fg::Float64, fb::Float64, fa::Float64,
                          sr::Float64, sg::Float64, sb::Float64, sa::Float64,
                          strokewidth::Float64, pattern::Vector{Float64},
                          linecap::Int64, joinstyle::Int64, miter_limit::Float64)
    (isempty(rings) || isempty(rings[1])) && return nothing
    begin_path(ctx)
    for ring in rings
        isempty(ring) && continue
        _ring_path!(ctx, ring)
    end
    set_fill_rgba(ctx, 255.0 * fr, 255.0 * fg, 255.0 * fb, fa)
    if length(rings) == 1
        fill_nonzero(ctx)
    else
        fill_evenodd(ctx)
    end
    _poly_stroke!(ctx, sr, sg, sb, sa, strokewidth, pattern, linecap, joinstyle, miter_limit)
    return nothing
end

"Axis-aligned rect polygon (translated from `create_shape_path!(::Rect2)`)."
function draw_poly_rect!(ctx, x::Float64, y::Float64, w::Float64, h::Float64,
                         fr::Float64, fg::Float64, fb::Float64, fa::Float64,
                         sr::Float64, sg::Float64, sb::Float64, sa::Float64,
                         strokewidth::Float64, pattern::Vector{Float64},
                         linecap::Int64, joinstyle::Int64, miter_limit::Float64)
    begin_path(ctx)
    rect(ctx, x, y, w, h)
    set_fill_rgba(ctx, 255.0 * fr, 255.0 * fg, 255.0 * fb, fa)
    fill_nonzero(ctx)
    _poly_stroke!(ctx, sr, sg, sb, sa, strokewidth, pattern, linecap, joinstyle, miter_limit)
    return nothing
end

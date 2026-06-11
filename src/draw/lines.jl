# VENDORED (translated) from CairoMakie v0.15.11 — src/lines.jl + src/utils.jl
# License: MIT (see VENDORED.md). Cairo→Canvas2D; divergences marked WASM-DIVERGENCE.
#
# Plain-data line drawing: positions arrive ALREADY PROJECTED to device pixels
# (y-down, like Cairo surfaces — canvas matches), colors in Makie's 0–1 float
# convention. Both CanvasMakie (extracting from real Makie's compute graph)
# and the static core call these with identical data.
#
# Closed-world discipline applies to this file: concrete types only.

const NO_DASH = Float64[]  # empty pattern = solid

# Makie linecap ints: 0 butt, 1 square, 2 round → ops table: 0 butt, 1 round, 2 square
_canvas_linecap(cap::Int64)::Int64 = cap == 1 ? Int64(2) : (cap == 2 ? Int64(1) : Int64(0))
# Makie joinstyle ints: 0 miter, 2 round, 3 bevel → ops table: 0 miter, 1 round, 2 bevel
_canvas_joinstyle(j::Int64)::Int64 = j == 2 ? Int64(1) : (j == 3 ? Int64(2) : Int64(0))

"""
    linestyle_to_pattern(linestyle, linewidth) -> Vector{Float64}

Makie linestyles are cumulative "absolute" endpoints; Canvas2D (like Cairo)
wants alternating on/off lengths — take the diff, scale by linewidth, pad to
even length. (Translated from CairoMakie `to_cairo_linestyle`.)
WASM-DIVERGENCE: solid is the empty vector, not `nothing` (closed-world).
"""
function linestyle_to_pattern(linestyle::Vector{Float64}, linewidth::Float64)
    pattern = diff(linestyle) .* linewidth
    isodd(length(pattern)) && push!(pattern, 0.0)
    return pattern
end

function set_line_style!(ctx, pattern::Vector{Float64}, linecap::Int64,
                         joinstyle::Int64, miter_limit::Float64)
    if isempty(pattern)
        set_line_dash4(ctx, 0.0, 0.0, 0.0, 0.0, Int64(0))
    else
        dash_buf_clear(ctx)
        for d in pattern
            dash_buf_push(ctx, d)
        end
        set_line_dash_buf(ctx)
    end
    set_line_cap(ctx, _canvas_linecap(linecap))
    set_line_join(ctx, _canvas_joinstyle(joinstyle))
    set_miter_limit(ctx, miter_limit)
    return nothing
end

_isnan2(p::NTuple{2,Float64}) = isnan(p[1]) || isnan(p[2])
_approx2(a::NTuple{2,Float64}, b::NTuple{2,Float64}) = isapprox(a[1], b[1]) && isapprox(a[2], b[2])

# Translated from CairoMakie `draw_single_lines`: NaN-segmented polyline.
# WASM-DIVERGENCE: Cairo's stroke() clears the path; canvas keeps it — so each
# run opens with an explicit begin_path instead of relying on implicit clears.
function draw_single_lines!(ctx, positions::Vector{NTuple{2,Float64}})
    isempty(positions) && return nothing
    n = length(positions)
    start = positions[1]
    for i in 1:n
        p = positions[i]
        if !_isnan2(p)
            if i == 1 || _isnan2(positions[i - 1])
                begin_path(ctx)
                move_to(ctx, p[1], p[2])
                start = p
            else
                line_to(ctx, p[1], p[2])
                if i == n || _isnan2(positions[i + 1])
                    _approx2(p, start) && close_path(ctx)
                    stroke(ctx)
                end
            end
        end
    end
    return nothing
end

# Translated from CairoMakie `draw_single_segments`: disjoint pairs.
function draw_single_segments!(ctx, positions::Vector{NTuple{2,Float64}})
    @assert iseven(length(positions))
    for i in 1:2:(length(positions) - 1)
        p1 = positions[i]
        p2 = positions[i + 1]
        if !(_isnan2(p1) || _isnan2(p2))
            begin_path(ctx)
            move_to(ctx, p1[1], p1[2])
            line_to(ctx, p2[1], p2[2])
            stroke(ctx)
        end
    end
    return nothing
end

"""
    draw_lines!(ctx, positions, is_lines, r, g, b, a, linewidth, pattern, linecap, joinstyle, miter_limit)

Uniform-style line drawing (translated from CairoMakie `draw_lineplot`'s
single-color branch). `r,g,b,a` in 0–1; `pattern` from
[`linestyle_to_pattern`](@ref) (empty = solid); cap/join in Makie's int
encoding; `miter_limit` already distance-converted (canvas and Cairo share
the same miter-limit definition).

Per-vertex colors/linewidths (CairoMakie `draw_multi`) are not implemented
yet — callers must reject arrays loudly (plan: D-008 burn-down).
"""
function draw_lines!(ctx, positions::Vector{NTuple{2,Float64}}, is_lines::Bool,
                     r::Float64, g::Float64, b::Float64, a::Float64,
                     linewidth::Float64, pattern::Vector{Float64},
                     linecap::Int64, joinstyle::Int64, miter_limit::Float64)
    isempty(positions) && return nothing
    set_line_style!(ctx, pattern, linecap, joinstyle, miter_limit)
    set_line_width(ctx, linewidth)
    set_stroke_rgba(ctx, 255.0 * r, 255.0 * g, 255.0 * b, a)
    if is_lines
        draw_single_lines!(ctx, positions)
    else
        draw_single_segments!(ctx, positions)
    end
    return nothing
end

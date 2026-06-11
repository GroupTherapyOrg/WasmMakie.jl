# VENDORED (translated) from CairoMakie v0.15.11 — src/lines.jl + src/utils.jl
# License: MIT (see VENDORED.md). Cairo→Canvas2D; divergences marked WASM-DIVERGENCE.
#
# Plain-data line drawing: positions arrive ALREADY PROJECTED to device pixels
# (y-down, like Cairo surfaces — canvas matches), colors in Makie's 0–1 float
# convention. Both CanvasMakie (extracting from real Makie's compute graph)
# and the static core call these with identical data.
#
# Closed-world discipline applies to this file: concrete types only.

const NO_DASH = Float64[]  # empty pattern = solid (host-side use only)
# WTGAP(pending, W-003): referencing a const non-isbits global (this empty
# Vector) from WasmTarget-compiled code traps `unreachable` at runtime —
# locally-constructed empties work. Compiled paths call no_dash() instead.
@inline no_dash() = Float64[]

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

function _set_dash_scaled!(ctx, dash::Vector{Float64}, lw::Float64)
    isempty(dash) && return nothing
    dash_buf_clear(ctx)
    for d in dash
        dash_buf_push(ctx, d * lw)
    end
    set_line_dash_buf(ctx)
    return nothing
end

function _stroke_solid!(ctx, c::NTuple{4,Float64}, lw::Float64, dash::Vector{Float64})
    # WASM-DIVERGENCE: clip interpolation can yield NaN colors for degenerate
    # segments; Cairo draws nothing visible for them, we skip the stroke
    # (behavior pinned by the clipping reference tests)
    if !(isfinite(c[1]) && isfinite(c[2]) && isfinite(c[3]) && isfinite(c[4]) && isfinite(lw))
        begin_path(ctx)
        return nothing
    end
    set_line_width(ctx, lw)
    _set_dash_scaled!(ctx, dash, lw)
    set_stroke_rgba(ctx, 255.0 * c[1], 255.0 * c[2], 255.0 * c[3], c[4])
    stroke(ctx)
    begin_path(ctx)  # WASM-DIVERGENCE: Cairo stroke clears the path; canvas keeps it
    return nothing
end

function _stroke_gradient!(ctx, p1::NTuple{2,Float64}, p2::NTuple{2,Float64},
                           c1::NTuple{4,Float64}, c2::NTuple{4,Float64},
                           lw::Float64, dash::Vector{Float64})
    if !(all(isfinite, c1) && all(isfinite, c2) && all(isfinite, p1) && all(isfinite, p2) && isfinite(lw))
        begin_path(ctx)
        return nothing
    end
    set_line_width(ctx, lw)
    _set_dash_scaled!(ctx, dash, lw)
    id = gradient_linear_new(ctx, p1[1], p1[2], p2[1], p2[2])
    gradient_add_stop(ctx, id, 0.0, 255.0 * c1[1], 255.0 * c1[2], 255.0 * c1[3], c1[4])
    gradient_add_stop(ctx, id, 1.0, 255.0 * c2[1], 255.0 * c2[2], 255.0 * c2[3], c2[4])
    set_stroke_gradient(ctx, id)
    stroke(ctx)
    begin_path(ctx)
    return nothing
end

# Translated from CairoMakie draw_multi_segments: per-pair color/width,
# gradient stroke when the endpoints differ.
function draw_multi_segments!(ctx, positions::Vector{NTuple{2,Float64}},
                              colors::Vector{NTuple{4,Float64}},
                              linewidths::Vector{Float64}, dash::Vector{Float64})
    @assert iseven(length(positions))
    for i in 1:2:length(positions)
        (_isnan2(positions[i]) || _isnan2(positions[i + 1])) && continue
        lw = linewidths[i]
        if lw != linewidths[i + 1]
            error("Cairo doesn't support two different line widths ($lw and $(linewidths[i + 1]) at the endpoints of a line.")
        end
        begin_path(ctx)
        move_to(ctx, positions[i][1], positions[i][2])
        line_to(ctx, positions[i + 1][1], positions[i + 1][2])
        c1 = colors[i]
        c2 = colors[i + 1]
        if c1 == c2
            _stroke_solid!(ctx, c1, lw, dash)
        else
            _stroke_gradient!(ctx, positions[i], positions[i + 1], c1, c2, lw, dash)
        end
    end
    gradient_clear_all(ctx)
    return nothing
end

# Translated from CairoMakie draw_multi_lines: run-stroking with per-point
# colors; color changes stroke the previous run and bridge with a gradient
# segment. The begin_path discipline replaces Cairo's implicit path clears.
function draw_multi_lines!(ctx, positions::Vector{NTuple{2,Float64}},
                           colors::Vector{NTuple{4,Float64}},
                           linewidths::Vector{Float64}, dash::Vector{Float64})
    isempty(positions) && return nothing
    @assert length(colors) == length(positions)
    @assert length(linewidths) == length(positions)

    prev_color = colors[1]
    prev_linewidth = linewidths[1]
    prev_position = positions[1]
    prev_nan = _isnan2(prev_position)
    prev_continued = false
    start = positions[1]

    begin_path(ctx)
    if !prev_nan
        move_to(ctx, prev_position[1], prev_position[2])
    end

    for i in 2:length(positions)
        this_position = positions[i]
        this_color = colors[i]
        this_nan = _isnan2(this_position)
        this_linewidth = linewidths[i]
        if this_nan
            if prev_continued
                _approx2(prev_position, start) && close_path(ctx)
                _stroke_solid!(ctx, prev_color, this_linewidth, dash)
            end
        end
        if prev_nan
            if !this_nan
                move_to(ctx, this_position[1], this_position[2])
                start = this_position
            end
        else
            if this_color == prev_color
                if !this_nan
                    this_linewidth != prev_linewidth && error("Encountered two different linewidth values $prev_linewidth and $this_linewidth in `lines` at index $(i - 1). Different linewidths in one line are only permitted in CairoMakie when separated by a NaN point.")
                    line_to(ctx, this_position[1], this_position[2])
                    prev_continued = true
                    if i == length(positions)
                        _approx2(this_position, start) && close_path(ctx)
                        _stroke_solid!(ctx, this_color, this_linewidth, dash)
                    end
                end
            else
                prev_continued = false
                _stroke_solid!(ctx, prev_color, prev_linewidth, dash)
                if !this_nan
                    this_linewidth != prev_linewidth && error("Encountered two different linewidth values $prev_linewidth and $this_linewidth in `lines` at index $(i - 1). Different linewidths in one line are only permitted in CairoMakie when separated by a NaN point.")
                    move_to(ctx, prev_position[1], prev_position[2])
                    line_to(ctx, this_position[1], this_position[2])
                    _stroke_gradient!(ctx, prev_position, this_position, prev_color, this_color, this_linewidth, dash)
                    move_to(ctx, this_position[1], this_position[2])
                end
            end
        end
        prev_nan = this_nan
        prev_color = this_color
        prev_linewidth = this_linewidth
        prev_position = this_position
    end
    gradient_clear_all(ctx)
    return nothing
end

"""
    draw_lines_multi!(ctx, positions, is_lines, colors, linewidths, dash, linecap, joinstyle, miter_limit)

Per-vertex colors/linewidths path (translated from CairoMakie `draw_multi`).
`dash` is the UNSCALED diff pattern — it is re-scaled by each stroke's width,
matching upstream. Cap/join/miter apply to all strokes.
"""
function draw_lines_multi!(ctx, positions::Vector{NTuple{2,Float64}}, is_lines::Bool,
                           colors::Vector{NTuple{4,Float64}}, linewidths::Vector{Float64},
                           dash::Vector{Float64}, linecap::Int64, joinstyle::Int64,
                           miter_limit::Float64)
    isempty(positions) && return nothing
    set_line_cap(ctx, _canvas_linecap(linecap))
    set_line_join(ctx, _canvas_joinstyle(joinstyle))
    set_miter_limit(ctx, miter_limit)
    isempty(dash) && set_line_dash4(ctx, 0.0, 0.0, 0.0, 0.0, Int64(0))
    if is_lines
        draw_multi_lines!(ctx, positions, colors, linewidths, dash)
    else
        draw_multi_segments!(ctx, positions, colors, linewidths, dash)
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

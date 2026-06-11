# The static core's render pipeline: Figure → ctx ops through the SAME
# draw/ layer CanvasMakie uses. Stateless recompute — every call walks the
# whole figure (the islands model).
#
# Decoration defaults captured from Makie Axis: grid (0,0,0,0.12) width 1,
# spines/ticks black width 1, axis background white. Marker geometry matches
# the D-003 oracle findings (:circle = r 0.3525·markersize, :rect = half
# 0.3157·markersize — Makie's scaled BezierPaths).

const GRID_COLOR = (0.0, 0.0, 0.0, 0.11999999731779099)
const CIRCLE_R = 0.3525    # oracle: Makie :circle BezierPath radius
const RECT_HALF = 0.3157   # oracle: Makie :rect BezierPath half-width

"Per-axis projection: data → device px (y-down) within the inner rect."
struct AxisTransform
    rx::Float64
    ry::Float64
    rw::Float64
    rh::Float64
    xmin::Float64
    xspan::Float64
    ymin::Float64
    yspan::Float64
end

function AxisTransform(irect::Rect2, res::ResolvedAxis)
    return AxisTransform(irect.x, irect.y, irect.w, irect.h,
                         res.xmin, res.xmax - res.xmin, res.ymin, res.ymax - res.ymin)
end

px_x(t::AxisTransform, x::Float64) = t.rx + (x - t.xmin) / t.xspan * t.rw
px_y(t::AxisTransform, y::Float64) = t.ry + t.rh - (y - t.ymin) / t.yspan * t.rh

function _project_xy(t::AxisTransform, xs::Vector{Float64}, ys::Vector{Float64})
    n = length(xs)
    out = Vector{NTuple{2,Float64}}(undef, n)
    for i in 1:n
        out[i] = (px_x(t, xs[i]), px_y(t, ys[i]))
    end
    return out
end

"""
    render!(fig::Figure, ctx)

Render the figure through any ctx (RecordingCtx host-side, WasmCtx in wasm).
"""
function render!(fig::Figure, ctx)
    bg = fig.backgroundcolor
    set_fill_rgba(ctx, 255.0 * bg[1], 255.0 * bg[2], 255.0 * bg[3], bg[4])
    fill_rect(ctx, 0.0, 0.0, fig.width, fig.height)

    nrows, ncols = grid_extents(fig)
    resolved = Vector{ResolvedAxis}(undef, length(fig.axes))
    prots = fill(Protrusions(), nrows * ncols)
    for (i, ax) in enumerate(fig.axes)
        resolved[i] = resolve_axis(ax)
        prots[(ax.row - 1) * ncols + ax.col] = resolved[i].prot
    end
    sizes_r = [auto_size() for _ in 1:nrows]
    sizes_c = [auto_size() for _ in 1:ncols]
    rects = solve_grid(0.0, 0.0, fig.width, fig.height, nrows, ncols, prots,
                       sizes_r, sizes_c, fig.rowgap, fig.colgap;
                       outside_pad = fig.padding)

    for (i, ax) in enumerate(fig.axes)
        irect = rects[(ax.row - 1) * ncols + ax.col]
        draw_axis!(ctx, ax, resolved[i], irect)
    end
    return nothing
end

function _set_stroke!(ctx, c::NTuple{4,Float64}, w::Float64)
    set_stroke_rgba(ctx, 255.0 * c[1], 255.0 * c[2], 255.0 * c[3], c[4])
    set_line_width(ctx, w)
    return nothing
end

function _hline!(ctx, x1::Float64, x2::Float64, y::Float64)
    begin_path(ctx)
    move_to(ctx, x1, y)
    line_to(ctx, x2, y)
    stroke(ctx)
    return nothing
end

function _vline!(ctx, x::Float64, y1::Float64, y2::Float64)
    begin_path(ctx)
    move_to(ctx, x, y1)
    line_to(ctx, x, y2)
    stroke(ctx)
    return nothing
end

function _text!(ctx, s::String, x::Float64, y::Float64, size::Float64,
                halign::Int64, valign::Int64, color::NTuple{4,Float64},
                weight::Int64 = Int64(400))
    set_font(ctx, Int64(0), size, weight, Int64(0))
    set_text_align(ctx, halign)      # 0 left, 1 center, 2 right
    set_text_baseline(ctx, valign)   # 0 alphabetic, 1 top, 2 middle, 3 bottom
    set_fill_rgba(ctx, 255.0 * color[1], 255.0 * color[2], 255.0 * color[3], color[4])
    text_buf_clear(ctx)
    for ch in s
        text_buf_push(ctx, Int64(codepoint(ch)))
    end
    fill_text_buf(ctx, x, y)
    return nothing
end

function draw_axis!(ctx, ax::Axis, res::ResolvedAxis, irect::Rect2)
    t = AxisTransform(irect, res)
    black = (0.0, 0.0, 0.0, 1.0)

    # axis background
    set_fill_rgba(ctx, 255.0, 255.0, 255.0, 1.0)
    fill_rect(ctx, irect.x, irect.y, irect.w, irect.h)

    # grid (under the data); minor grid first (Makie z-order)
    set_line_dash4(ctx, 0.0, 0.0, 0.0, 0.0, Int64(0))
    if ax.xminorgridvisible
        _set_stroke!(ctx, MINORGRID_COLOR, 1.0)
        for v in _minor_positions(res.xticks, ax.xminorticks_n)
            _vline!(ctx, px_x(t, v), irect.y, irect.y + irect.h)
        end
    end
    if ax.yminorgridvisible
        _set_stroke!(ctx, MINORGRID_COLOR, 1.0)
        for v in _minor_positions(res.yticks, ax.yminorticks_n)
            _hline!(ctx, irect.x, irect.x + irect.w, px_y(t, v))
        end
    end
    _set_stroke!(ctx, GRID_COLOR, 1.0)
    if ax.xgridvisible
        for v in res.xticks
            _vline!(ctx, px_x(t, v), irect.y, irect.y + irect.h)
        end
    end
    if ax.ygridvisible
        for v in res.yticks
            _hline!(ctx, irect.x, irect.x + irect.w, px_y(t, v))
        end
    end

    # plots, clipped to the axis rect
    save(ctx)
    begin_path(ctx)
    rect(ctx, t.rx, t.ry, t.rw, t.rh)
    clip_nonzero(ctx)
    for (kind, idx) in ax.plot_order
        if kind == PLOT_LINES
            p = ax.lines[idx]
            pts = _project_xy(t, p.x, p.y)
            pattern = p.linestyle == LINESTYLE_SOLID ? no_dash() :
                      p.linestyle == LINESTYLE_DASH ? linestyle_to_pattern([0.0, 3.0, 4.0], p.linewidth) :
                      p.linestyle == LINESTYLE_DOT ? linestyle_to_pattern([0.0, 1.0, 2.0], p.linewidth) :
                      linestyle_to_pattern([0.0, 3.0, 4.0, 5.0, 6.0], p.linewidth)
            draw_lines!(ctx, pts, true, p.color[1], p.color[2], p.color[3], p.color[4],
                        p.linewidth, pattern, THEME_LINECAP, THEME_JOINSTYLE,
                        2.0 / sin(THEME_MITER_LIMIT_ANGLE / 2.0) / 2.0)
        elseif kind == PLOT_SCATTER
            p = ax.scatters[idx]
            for i in eachindex(p.x)
                mx = px_x(t, p.x[i])
                my = px_y(t, p.y[i])
                (isfinite(mx) && isfinite(my)) || continue
                if p.marker == MARKER_RECT
                    h = RECT_HALF * p.markersize
                    draw_marker_rect!(ctx, mx, my, 2.0 * h, 0.0, 0.0, 2.0 * h,
                                      p.color[1], p.color[2], p.color[3], p.color[4],
                                      p.strokecolor[1], p.strokecolor[2], p.strokecolor[3], p.strokecolor[4],
                                      p.strokewidth)
                else  # circle (and utriangle approximation until paths land here)
                    r = CIRCLE_R * p.markersize
                    draw_marker_circle!(ctx, mx, my, 2.0 * r, 0.0, 0.0, 2.0 * r,
                                        p.color[1], p.color[2], p.color[3], p.color[4],
                                        p.strokecolor[1], p.strokecolor[2], p.strokecolor[3], p.strokecolor[4],
                                        p.strokewidth)
                end
            end
        elseif kind == PLOT_BARPLOT
            p = ax.bars[idx]
            n = length(p.x)
            barw = n > 1 ? (1.0 - p.gap) * abs(px_x(t, p.x[2]) - px_x(t, p.x[1])) :
                   (1.0 - p.gap) * t.rw * 0.5
            y0 = px_y(t, 0.0)
            for i in 1:n
                cx = px_x(t, p.x[i])
                ytop = px_y(t, p.y[i])
                draw_poly_rect!(ctx, cx - 0.5 * barw, min(y0, ytop), barw, abs(y0 - ytop),
                                p.color[1], p.color[2], p.color[3], p.color[4],
                                p.strokecolor[1], p.strokecolor[2], p.strokecolor[3], p.strokecolor[4],
                                p.strokewidth, no_dash(), THEME_LINECAP, THEME_JOINSTYLE, 4.0)
            end
        elseif kind == PLOT_HEATMAP
            p = ax.heatmaps[idx]
            nx = p.nx
            ny = p.ny
            lo = isnan(p.colorrange_min) ? minimum(p.values) : p.colorrange_min
            hi = isnan(p.colorrange_max) ? maximum(p.values) : p.colorrange_max
            pixels = Vector{NTuple{4,Float64}}(undef, nx * ny)
            for k in 1:(nx * ny)
                pixels[k] = interpolated_getindex(VIRIDIS, p.values[k], lo, hi)
            end
            x0 = px_x(t, p.xs[1]); x1 = px_x(t, p.xs[end])
            y0p = px_y(t, p.ys[1]); y1p = px_y(t, p.ys[end])
            draw_image_scaled!(ctx, pixels, Int64(nx), Int64(ny), x0, y0p, x1 - x0, y1p - y0p, false)
        elseif kind == PLOT_IMAGE
            p = ax.images[idx]
            x0 = px_x(t, p.x0); x1 = px_x(t, p.x1)
            y0p = px_y(t, p.y0); y1p = px_y(t, p.y1)
            draw_image_scaled!(ctx, p.pixels, p.ni, p.nj, x0, y0p, x1 - x0, y1p - y0p, p.interpolate)
        end
    end
    restore(ctx)

    # spines (over the data), per-side visibility (L-001)
    _set_stroke!(ctx, (0.0, 0.0, 0.0, 1.0), AXIS_SPINEWIDTH)
    set_line_dash4(ctx, 0.0, 0.0, 0.0, 0.0, Int64(0))
    ax.leftspinevisible &&
        _vline!(ctx, irect.x, irect.y, irect.y + irect.h)
    ax.rightspinevisible &&
        _vline!(ctx, irect.x + irect.w, irect.y, irect.y + irect.h)
    ax.topspinevisible &&
        _hline!(ctx, irect.x, irect.x + irect.w, irect.y)
    ax.bottomspinevisible &&
        _hline!(ctx, irect.x, irect.x + irect.w, irect.y + irect.h)

    # ticks + tick labels (visibility-gated; minor ticks size 3)
    tlsize = THEME_FONTSIZE
    if ax.xminorticksvisible
        for v in _minor_positions(res.xticks, ax.xminorticks_n)
            x = px_x(t, v)
            _vline!(ctx, x, irect.y + irect.h, irect.y + irect.h + AXIS_MINORTICKSIZE)
        end
    end
    if ax.yminorticksvisible
        for v in _minor_positions(res.yticks, ax.yminorticks_n)
            _hline!(ctx, irect.x - AXIS_MINORTICKSIZE, irect.x, px_y(t, v))
        end
    end
    for (v, lab) in zip(res.xticks, res.xticklabels)
        x = px_x(t, v)
        ax.xticksvisible &&
            _vline!(ctx, x, irect.y + irect.h, irect.y + irect.h + AXIS_TICKSIZE)
        ax.xticklabelsvisible &&
            _text!(ctx, lab.text, x,
                   irect.y + irect.h + AXIS_SPINEWIDTH + AXIS_TICKSIZE + AXIS_XTICKLABELPAD,
                   tlsize, Int64(1), Int64(1), THEME_TEXTCOLOR)
    end
    for (v, lab) in zip(res.yticks, res.yticklabels)
        y = px_y(t, v)
        ax.yticksvisible &&
            _hline!(ctx, irect.x - AXIS_TICKSIZE, irect.x, y)
        ax.yticklabelsvisible &&
            _text!(ctx, lab.text,
                   irect.x - AXIS_SPINEWIDTH - AXIS_TICKSIZE - AXIS_YTICKLABELPAD, y,
                   tlsize, Int64(2), Int64(2), THEME_TEXTCOLOR)
    end

    # title (BOLD — Makie titlefont :bold) + subtitle + axis labels
    title_x = ax.titlealign == 0 ? irect.x :
              ax.titlealign == 2 ? irect.x + irect.w : irect.x + 0.5 * irect.w
    title_halign = ax.titlealign == 0 ? Int64(0) :
                   ax.titlealign == 2 ? Int64(2) : Int64(1)
    sub_h = (ax.subtitlevisible && !isempty(ax.subtitle)) ?
            TEXT_HEIGHT_RATIO * ax.subtitlesize + ax.subtitlegap : 0.0
    if ax.subtitlevisible && !isempty(ax.subtitle)
        _text!(ctx, ax.subtitle, title_x, irect.y - ax.subtitlegap,
               ax.subtitlesize, title_halign, Int64(3), THEME_TEXTCOLOR)
    end
    if ax.titlevisible && !isempty(ax.title)
        _text!(ctx, ax.title, title_x, irect.y - sub_h - ax.titlegap,
               ax.titlesize, title_halign, Int64(3), THEME_TEXTCOLOR, Int64(700))
    end
    if ax.xlabelvisible && !isempty(ax.xlabel)
        _text!(ctx, ax.xlabel, irect.x + 0.5 * irect.w,
               irect.y + irect.h + AXIS_TICKSIZE + AXIS_XTICKLABELPAD +
               TEXT_HEIGHT_RATIO * tlsize + AXIS_LABELPADDING,
               ax.xlabelsize, Int64(1), Int64(1), THEME_TEXTCOLOR)
    end
    if ax.ylabelvisible && !isempty(ax.ylabel)
        save(ctx)
        translate(ctx, irect.x - res.prot.l + TEXT_HEIGHT_RATIO * ax.ylabelsize * 0.5,
                  irect.y + 0.5 * irect.h)
        rotate(ctx, -pi / 2)
        _text!(ctx, ax.ylabel, 0.0, 0.0, ax.ylabelsize, Int64(1), Int64(2), THEME_TEXTCOLOR)
        restore(ctx)
    end
    return nothing
end

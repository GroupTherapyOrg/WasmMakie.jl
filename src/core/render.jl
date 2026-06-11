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
        _merge_span_prots!(prots, resolved[i].prot, ncols,
                           ax.row, ax.row2, ax.col, ax.col2)
    end
    for cb in fig.colorbars
        _merge_span_prots!(prots, _colorbar_protrusions(cb), ncols,
                           cb.row, cb.row2, cb.col, cb.col2)
    end
    sizes_r = [i <= length(fig.rowsizes) ? fig.rowsizes[i] : auto_size() for i in 1:nrows]
    sizes_c = [i <= length(fig.colsizes) ? fig.colsizes[i] : auto_size() for i in 1:ncols]
    # a column holding only vertical colorbars gets the fixed 12px bar width
    # (Makie Colorbar size); same for rows of horizontal bars
    for cb in fig.colorbars
        if cb.vertical && sizes_c[cb.col].kind == SIZE_AUTO &&
                !any(a -> a.col <= cb.col <= a.col2, fig.axes)
            sizes_c[cb.col] = fixed_size(COLORBAR_SIZE)
        elseif !cb.vertical && sizes_r[cb.row].kind == SIZE_AUTO &&
                !any(a -> a.row <= cb.row <= a.row2, fig.axes)
            sizes_r[cb.row] = fixed_size(COLORBAR_SIZE)
        end
    end
    rects = solve_grid(0.0, 0.0, fig.width, fig.height, nrows, ncols, prots,
                       sizes_r, sizes_c, fig.rowgap, fig.colgap;
                       outside_pad = fig.padding)

    for (i, ax) in enumerate(fig.axes)
        irect = _span_rect(rects, ncols, ax.row, ax.row2, ax.col, ax.col2)
        draw_axis!(ctx, ax, resolved[i], irect)
    end
    for cb in fig.colorbars
        irect = _span_rect(rects, ncols, cb.row, cb.row2, cb.col, cb.col2)
        draw_colorbar!(ctx, cb, irect)
    end
    return nothing
end

# spanning elements contribute each protrusion side to the EDGE cells of
# their span (GridLayoutBase semantics), max-merged with cohabitants
function _merge_span_prots!(prots::Vector{Protrusions}, p::Protrusions, ncols::Int64,
                            r1::Int64, r2::Int64, c1::Int64, c2::Int64)
    for r in r1:r2
        for c in c1:c2
            i = (r - 1) * ncols + c
            old = prots[i]
            prots[i] = Protrusions(
                c == c1 ? max(old.l, p.l) : old.l,
                c == c2 ? max(old.r, p.r) : old.r,
                r == r1 ? max(old.t, p.t) : old.t,
                r == r2 ? max(old.b, p.b) : old.b)
        end
    end
    return nothing
end

"Bounding rect of a span's inner cells."
function _span_rect(rects::Vector{Rect2}, ncols::Int64,
                    r1::Int64, r2::Int64, c1::Int64, c2::Int64)
    a = rects[(r1 - 1) * ncols + c1]
    b = rects[(r2 - 1) * ncols + c2]
    return Rect2(a.x, a.y, b.x + b.w - a.x, b.y + b.h - a.y)
end

# ── L-003: Colorbar (Makie @Block defaults: size 12, ticksize 5,
# ticklabelpad 3, labelpadding 5, spine w1, vertical + flipaxis right) ──────
const COLORBAR_SIZE = 12.0
const COLORBAR_TICKLABELPAD = 3.0
const COLORBAR_LABELPADDING = 5.0

function _colorbar_protrusions(cb::Colorbar)
    ticks = wilkinson_ticks_default(cb.lo, cb.hi)
    labels = format_ticks_auto(ticks)
    tlsize = THEME_FONTSIZE
    if cb.vertical
        right = AXIS_TICKSIZE + COLORBAR_TICKLABELPAD + _max_label_width(labels, tlsize)
        if !isempty(cb.label)
            right += COLORBAR_LABELPADDING + TEXT_HEIGHT_RATIO * tlsize
        end
        return Protrusions(0.0, right, 0.0, 0.0)
    else
        top = AXIS_TICKSIZE + COLORBAR_TICKLABELPAD + TEXT_HEIGHT_RATIO * tlsize
        if !isempty(cb.label)
            top += COLORBAR_LABELPADDING + TEXT_HEIGHT_RATIO * tlsize
        end
        return Protrusions(0.0, 0.0, top, 0.0)
    end
end

function draw_colorbar!(ctx, cb::Colorbar, irect::Rect2)
    # the colormap as a 1×256 image strip (CairoMakie rasterizes the same way)
    n = Int64(length(VIRIDIS))
    pixels = Vector{NTuple{4,Float64}}(undef, n)
    if cb.vertical
        for j in 1:n
            pixels[j] = VIRIDIS[n - j + 1]   # top = hi
        end
        draw_image_scaled!(ctx, pixels, Int64(1), n,
                           irect.x, irect.y, irect.w, irect.h, true)
    else
        for j in 1:n
            pixels[j] = VIRIDIS[j]
        end
        draw_image_scaled!(ctx, pixels, n, Int64(1),
                           irect.x, irect.y, irect.w, irect.h, true)
    end

    # spine
    _set_stroke!(ctx, (0.0, 0.0, 0.0, 1.0), AXIS_SPINEWIDTH)
    set_line_dash4(ctx, 0.0, 0.0, 0.0, 0.0, Int64(0))
    begin_path(ctx)
    rect(ctx, irect.x, irect.y, irect.w, irect.h)
    stroke(ctx)

    # ticks + labels on the flip side (right / top)
    ticks = wilkinson_ticks_default(cb.lo, cb.hi)
    labels = format_ticks_auto(ticks)
    tlsize = THEME_FONTSIZE
    span = cb.hi - cb.lo
    for (v, lab) in zip(ticks, labels)
        frac = span == 0.0 ? 0.5 : (v - cb.lo) / span
        if cb.vertical
            y = irect.y + irect.h - frac * irect.h
            _hline!(ctx, irect.x + irect.w, irect.x + irect.w + AXIS_TICKSIZE, y)
            _text!(ctx, lab.text,
                   irect.x + irect.w + AXIS_SPINEWIDTH + AXIS_TICKSIZE + COLORBAR_TICKLABELPAD,
                   y, tlsize, Int64(0), Int64(2), THEME_TEXTCOLOR)
        else
            x = irect.x + frac * irect.w
            _vline!(ctx, x, irect.y - AXIS_TICKSIZE, irect.y)
            _text!(ctx, lab.text, x,
                   irect.y - AXIS_SPINEWIDTH - AXIS_TICKSIZE - COLORBAR_TICKLABELPAD,
                   tlsize, Int64(1), Int64(3), THEME_TEXTCOLOR)
        end
    end

    if !isempty(cb.label)
        if cb.vertical
            tick_w = _max_label_width(labels, tlsize)
            save(ctx)
            translate(ctx, irect.x + irect.w + AXIS_TICKSIZE + COLORBAR_TICKLABELPAD +
                           tick_w + COLORBAR_LABELPADDING + 0.5 * TEXT_HEIGHT_RATIO * tlsize,
                      irect.y + 0.5 * irect.h)
            rotate(ctx, pi / 2)
            _text!(ctx, cb.label, 0.0, 0.0, tlsize, Int64(1), Int64(2), THEME_TEXTCOLOR)
            restore(ctx)
        else
            _text!(ctx, cb.label, irect.x + 0.5 * irect.w,
                   irect.y - AXIS_TICKSIZE - COLORBAR_TICKLABELPAD -
                   TEXT_HEIGHT_RATIO * tlsize - COLORBAR_LABELPADDING,
                   tlsize, Int64(1), Int64(3), THEME_TEXTCOLOR)
        end
    end
    return nothing
end

function fill_rect_rgba!(ctx, x::Float64, y::Float64, w::Float64, h::Float64,
                         c::NTuple{4,Float64})
    set_fill_rgba(ctx, 255.0 * c[1], 255.0 * c[2], 255.0 * c[3], c[4])
    fill_rect(ctx, x, y, w, h)
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
            barw = p.width / t.xspan * t.rw   # data-unit width → px
            for i in 1:n
                cx = px_x(t, p.x[i])
                base = isempty(p.fillto) ? 0.0 : p.fillto[i]
                y0 = px_y(t, base)
                ytop = px_y(t, p.y[i])
                bc = isempty(p.colors) ? p.color : p.colors[i]
                draw_poly_rect!(ctx, cx - 0.5 * barw, min(y0, ytop), barw, abs(y0 - ytop),
                                bc[1], bc[2], bc[3], bc[4],
                                p.strokecolor[1], p.strokecolor[2], p.strokecolor[3], p.strokecolor[4],
                                p.strokewidth, no_dash(), THEME_LINECAP, THEME_JOINSTYLE, 4.0)
            end
        elseif kind == PLOT_HVLINES
            p = ax.hvlines[idx]
            pattern = p.linestyle == LINESTYLE_SOLID ? no_dash() :
                      p.linestyle == LINESTYLE_DASH ? linestyle_to_pattern([0.0, 3.0, 4.0], p.linewidth) :
                      p.linestyle == LINESTYLE_DOT ? linestyle_to_pattern([0.0, 1.0, 2.0], p.linewidth) :
                      linestyle_to_pattern([0.0, 3.0, 4.0, 5.0, 6.0], p.linewidth)
            for v in p.values
                pts = p.horizontal ?
                    NTuple{2,Float64}[(t.rx, px_y(t, v)), (t.rx + t.rw, px_y(t, v))] :
                    NTuple{2,Float64}[(px_x(t, v), t.ry), (px_x(t, v), t.ry + t.rh)]
                draw_lines!(ctx, pts, true, p.color[1], p.color[2], p.color[3], p.color[4],
                            p.linewidth, pattern, THEME_LINECAP, THEME_JOINSTYLE, 10.0)
            end
        elseif kind == PLOT_HVSPAN
            p = ax.hvspans[idx]
            for i in eachindex(p.los)
                if p.horizontal
                    y1 = px_y(t, p.his[i]); y2 = px_y(t, p.los[i])
                    fill_rect_rgba!(ctx, t.rx, y1, t.rw, y2 - y1, p.color)
                else
                    x1 = px_x(t, p.los[i]); x2 = px_x(t, p.his[i])
                    fill_rect_rgba!(ctx, x1, t.ry, x2 - x1, t.rh, p.color)
                end
            end
        elseif kind == PLOT_ABLINES
            p = ax.ablines[idx]
            pattern = p.linestyle == LINESTYLE_SOLID ? no_dash() :
                      p.linestyle == LINESTYLE_DASH ? linestyle_to_pattern([0.0, 3.0, 4.0], p.linewidth) :
                      p.linestyle == LINESTYLE_DOT ? linestyle_to_pattern([0.0, 1.0, 2.0], p.linewidth) :
                      linestyle_to_pattern([0.0, 3.0, 4.0, 5.0, 6.0], p.linewidth)
            for i in eachindex(p.intercepts)
                a = p.intercepts[i]
                b = p.slopes[i]
                y_at_min = a + b * t.xmin
                y_at_max = a + b * (t.xmin + t.xspan)
                pts = NTuple{2,Float64}[(t.rx, px_y(t, y_at_min)),
                                        (t.rx + t.rw, px_y(t, y_at_max))]
                draw_lines!(ctx, pts, true, p.color[1], p.color[2], p.color[3], p.color[4],
                            p.linewidth, pattern, THEME_LINECAP, THEME_JOINSTYLE, 10.0)
            end
        elseif kind == PLOT_SEGMENTS
            p = ax.segments[idx]
            pts = _project_xy(t, p.x, p.y)
            pattern = p.linestyle == LINESTYLE_SOLID ? no_dash() :
                      p.linestyle == LINESTYLE_DASH ? linestyle_to_pattern([0.0, 3.0, 4.0], p.linewidth) :
                      p.linestyle == LINESTYLE_DOT ? linestyle_to_pattern([0.0, 1.0, 2.0], p.linewidth) :
                      linestyle_to_pattern([0.0, 3.0, 4.0, 5.0, 6.0], p.linewidth)
            set_line_cap(ctx, THEME_LINECAP)
            cols = Vector{NTuple{4,Float64}}(undef, length(pts))
            lws = Vector{Float64}(undef, length(pts))
            for k in eachindex(pts)
                cols[k] = p.color
                lws[k] = p.linewidth
            end
            draw_multi_segments!(ctx, pts, cols, lws, pattern)
        elseif kind == PLOT_FILLEDCURVE
            p = ax.filledcurves[idx]
            ring = Vector{NTuple{2,Float64}}(undef, length(p.x) + 2)
            for i in eachindex(p.x)
                ring[i] = (px_x(t, p.x[i]), px_y(t, p.y[i]))
            end
            ring[length(p.x) + 1] = (px_x(t, p.x[end]), px_y(t, p.baseline))
            ring[length(p.x) + 2] = (px_x(t, p.x[1]), px_y(t, p.baseline))
            rings = Vector{Vector{NTuple{2,Float64}}}(undef, 1)
            rings[1] = ring
            draw_poly_rings!(ctx, rings,
                             p.color[1], p.color[2], p.color[3], p.color[4],
                             p.strokecolor[1], p.strokecolor[2], p.strokecolor[3], p.strokecolor[4],
                             p.strokewidth, no_dash(), THEME_LINECAP, THEME_JOINSTYLE, 4.0)
        elseif kind == PLOT_BAND
            p = ax.bands[idx]
            n = length(p.x)
            ring = Vector{NTuple{2,Float64}}(undef, 2 * n)
            for i in 1:n
                ring[i] = (px_x(t, p.x[i]), px_y(t, p.yhigh[i]))
            end
            for i in 1:n
                ring[n + i] = (px_x(t, p.x[n - i + 1]), px_y(t, p.ylow[n - i + 1]))
            end
            rings = Vector{Vector{NTuple{2,Float64}}}(undef, 1)
            rings[1] = ring
            draw_poly_rings!(ctx, rings,
                             p.color[1], p.color[2], p.color[3], p.color[4],
                             0.0, 0.0, 0.0, 1.0, 0.0, no_dash(),
                             THEME_LINECAP, THEME_JOINSTYLE, 4.0)
        elseif kind == PLOT_POLY
            p = ax.polys[idx]
            nrings = length(p.ring_starts)
            rings = Vector{Vector{NTuple{2,Float64}}}(undef, nrings)
            for ri in 1:nrings
                lo = p.ring_starts[ri]
                hi = ri < nrings ? p.ring_starts[ri + 1] - 1 : length(p.xs)
                ring = Vector{NTuple{2,Float64}}(undef, hi - lo + 1)
                for i in lo:hi
                    ring[i - lo + 1] = (px_x(t, p.xs[i]), px_y(t, p.ys[i]))
                end
                rings[ri] = ring
            end
            draw_poly_rings!(ctx, rings,
                             p.color[1], p.color[2], p.color[3], p.color[4],
                             p.strokecolor[1], p.strokecolor[2], p.strokecolor[3], p.strokecolor[4],
                             p.strokewidth, no_dash(), THEME_LINECAP, THEME_JOINSTYLE, 4.0)
        elseif kind == PLOT_MESH
            p = ax.meshes[idx]
            n = length(p.vx)
            mw = Int64(round(t.rw))
            mh = Int64(round(t.rh))
            fx = Vector{Float64}(undef, n)
            fy = Vector{Float64}(undef, n)
            for i in 1:n
                fx[i] = px_x(t, p.vx[i]) - t.rx
                fy[i] = px_y(t, p.vy[i]) - t.ry
            end
            draw_mesh!(ctx, fx, fy, p.vz, p.vr, p.vg, p.vb, p.va, p.faces,
                       t.rx, t.ry, mw, mh)
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

    ax.legend_active && _draw_legend!(ctx, ax, irect)
    return nothing
end

# ── L-002: axislegend (Makie @Block Legend defaults: padding 6, margin 6,
# patchsize 20×20, patchlabelgap 5, rowgap 3, colgap 16, frame black w1,
# white background; swatches use the plot's own attributes) ────────────────
const LEGEND_PAD = 6.0
const LEGEND_MARGIN = 6.0
const LEGEND_PATCH = 20.0
const LEGEND_PATCHLABELGAP = 5.0
const LEGEND_ROWGAP = 3.0
const LEGEND_COLGAP = 16.0

function _draw_legend!(ctx, ax::Axis, irect::Rect2)
    # entries in plot order: (kind, idx) with nonempty labels
    kinds = Int64[]
    idxs = Int64[]
    labels = String[]
    for (kind, idx) in ax.plot_order
        lab = kind == PLOT_LINES ? ax.lines[idx].label :
              kind == PLOT_SCATTER ? ax.scatters[idx].label :
              kind == PLOT_BARPLOT ? ax.bars[idx].label : ""
        if !isempty(lab)
            push!(kinds, kind)
            push!(idxs, idx)
            push!(labels, lab)
        end
    end
    n = length(labels)
    n == 0 && return nothing

    lsize = THEME_FONTSIZE
    nbanks = ax.legend_nbanks < 1 ? Int64(1) : ax.legend_nbanks
    nrows = Int64(cld(n, nbanks))

    # per-bank widths from table-metric label advances
    t = TableExtents()
    bankw = Float64[]
    for b in 1:nbanks
        w = 0.0
        for r in 1:nrows
            i = (b - 1) * nrows + r
            i <= n || continue
            lw = 0.0
            for c in labels[i]
                lw += glyph_extent!(t, nothing, Int64(codepoint(c)), Int64(0),
                                    Int64(400), Int64(0)).hadvance
            end
            lw * lsize > w && (w = lw * lsize)
        end
        push!(bankw, LEGEND_PATCH + LEGEND_PATCHLABELGAP + w)
    end
    total_w = 2.0 * LEGEND_PAD + LEGEND_COLGAP * Float64(nbanks - 1)
    for w in bankw
        total_w += w
    end
    rowh = LEGEND_PATCH  # > label line height at default sizes
    total_h = 2.0 * LEGEND_PAD + Float64(nrows) * rowh + Float64(nrows - 1) * LEGEND_ROWGAP

    x0 = ax.legend_halign == 0 ? irect.x + LEGEND_MARGIN :
         ax.legend_halign == 1 ? irect.x + 0.5 * (irect.w - total_w) :
         irect.x + irect.w - LEGEND_MARGIN - total_w
    y0 = ax.legend_valign == 2 ? irect.y + LEGEND_MARGIN :
         ax.legend_valign == 1 ? irect.y + 0.5 * (irect.h - total_h) :
         irect.y + irect.h - LEGEND_MARGIN - total_h

    # background + frame
    set_fill_rgba(ctx, 255.0, 255.0, 255.0, 1.0)
    fill_rect(ctx, x0, y0, total_w, total_h)
    _set_stroke!(ctx, (0.0, 0.0, 0.0, 1.0), 1.0)
    set_line_dash4(ctx, 0.0, 0.0, 0.0, 0.0, Int64(0))
    begin_path(ctx)
    rect(ctx, x0, y0, total_w, total_h)
    stroke(ctx)

    bx = x0 + LEGEND_PAD
    for b in 1:nbanks
        for r in 1:nrows
            i = (b - 1) * nrows + r
            i <= n || continue
            py = y0 + LEGEND_PAD + Float64(r - 1) * (rowh + LEGEND_ROWGAP)
            cy = py + 0.5 * rowh
            kind = kinds[i]
            idx = idxs[i]
            if kind == PLOT_LINES
                pl = ax.lines[idx]
                pattern = pl.linestyle == LINESTYLE_SOLID ? no_dash() :
                          pl.linestyle == LINESTYLE_DASH ? linestyle_to_pattern([0.0, 3.0, 4.0], pl.linewidth) :
                          pl.linestyle == LINESTYLE_DOT ? linestyle_to_pattern([0.0, 1.0, 2.0], pl.linewidth) :
                          linestyle_to_pattern([0.0, 3.0, 4.0, 5.0, 6.0], pl.linewidth)
                pts = NTuple{2,Float64}[(bx, cy), (bx + LEGEND_PATCH, cy)]
                draw_lines!(ctx, pts, true, pl.color[1], pl.color[2], pl.color[3], pl.color[4],
                            pl.linewidth, pattern, THEME_LINECAP, THEME_JOINSTYLE, 10.0)
            elseif kind == PLOT_SCATTER
                ps = ax.scatters[idx]
                mx = bx + 0.5 * LEGEND_PATCH
                if ps.marker == MARKER_RECT
                    h = RECT_HALF * ps.markersize
                    draw_marker_rect!(ctx, mx, cy, 2.0 * h, 0.0, 0.0, 2.0 * h,
                                      ps.color[1], ps.color[2], ps.color[3], ps.color[4],
                                      ps.strokecolor[1], ps.strokecolor[2], ps.strokecolor[3], ps.strokecolor[4],
                                      ps.strokewidth)
                else
                    rr = CIRCLE_R * ps.markersize
                    draw_marker_circle!(ctx, mx, cy, 2.0 * rr, 0.0, 0.0, 2.0 * rr,
                                        ps.color[1], ps.color[2], ps.color[3], ps.color[4],
                                        ps.strokecolor[1], ps.strokecolor[2], ps.strokecolor[3], ps.strokecolor[4],
                                        ps.strokewidth)
                end
            else  # PLOT_BARPLOT — PolyElement fills the patch
                pb = ax.bars[idx]
                draw_poly_rect!(ctx, bx, py, LEGEND_PATCH, rowh,
                                pb.color[1], pb.color[2], pb.color[3], pb.color[4],
                                0.0, 0.0, 0.0, 1.0, 0.0, no_dash(),
                                THEME_LINECAP, THEME_JOINSTYLE, 4.0)
            end
            _text!(ctx, labels[i], bx + LEGEND_PATCH + LEGEND_PATCHLABELGAP, cy,
                   lsize, Int64(0), Int64(2), THEME_TEXTCOLOR)
        end
        bx += bankw[b] + LEGEND_COLGAP
    end
    return nothing
end

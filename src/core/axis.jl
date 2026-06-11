# Axis resolution — limits/autolimits, tick integration, decoration model.
#
# Mirrors Makie's Axis semantics (oracle-pinned): autolimits expand the data
# union by 5% margins per side (xautolimitmargin defaults); empty or
# degenerate spans fall back to (0, 10); user limits (non-NaN Axis fields)
# override. Tick values are `locateticks` (the `automatic` path), labels the
# C-003 formatter.
#
# Protrusions use the T-004 deterministic metric tables: heights are the
# font-level line box (ascender − descender = 1.165em for TGH — the earlier
# calibrated TEXT_HEIGHT_RATIO was exactly this), widths the ink extent of
# the laid-out label through the vendored layouting.

# Makie Axis decoration constants (captured from default attributes)
const AXIS_TICKSIZE = 5.0
const AXIS_TICKLABELPAD = 2.0
const AXIS_LABELPADDING = 3.0
const AXIS_SPINEWIDTH = 1.0
const AXIS_TITLEGAP = 4.0
# full line height / fontsize == FreeType (ascender − descender)/em for TGH
# (T-004 tables confirmed the calibration: 0.947 + 0.218 = 1.165)
const TEXT_HEIGHT_RATIO = 1.165

"Fully resolved axis: final limits, ticks, labels, and protrusions."
struct ResolvedAxis
    xmin::Float64
    xmax::Float64
    ymin::Float64
    ymax::Float64
    xticks::Vector{Float64}
    xticklabels::Vector{TickLabel}
    yticks::Vector{Float64}
    yticklabels::Vector{TickLabel}
    prot::Protrusions
end

function _plots_limits(ax::Axis)
    xlo = Inf; xhi = -Inf; ylo = Inf; yhi = -Inf
    for (kind, idx) in ax.plot_order
        l = kind == PLOT_LINES ? data_limits(ax.lines[idx]) :
            kind == PLOT_SCATTER ? data_limits(ax.scatters[idx]) :
            kind == PLOT_BARPLOT ? data_limits(ax.bars[idx]) :
            kind == PLOT_HEATMAP ? data_limits(ax.heatmaps[idx]) :
            data_limits(ax.images[idx])
        l[1] < xlo && (xlo = l[1])
        l[2] > xhi && (xhi = l[2])
        l[3] < ylo && (ylo = l[3])
        l[4] > yhi && (yhi = l[4])
    end
    return xlo, xhi, ylo, yhi
end

# one dimension: margins, degenerate fallback (oracle: → 0..10), user override
function _final_1d(lo::Float64, hi::Float64, user_lo::Float64, user_hi::Float64,
                   margin::Float64)
    if !isfinite(lo) || !isfinite(hi) || lo == hi
        lo, hi = 0.0, 10.0
    else
        span = hi - lo
        lo -= margin * span
        hi += margin * span
    end
    isnan(user_lo) || (lo = user_lo)
    isnan(user_hi) || (hi = user_hi)
    return lo, hi
end

"""
    final_limits(ax) -> (xmin, xmax, ymin, ymax)

Makie's autolimits: 5% margins around the plots' data union; (0, 10) when
empty/degenerate; user-set Axis limits override per side.
"""
function final_limits(ax::Axis)
    xlo, xhi, ylo, yhi = _plots_limits(ax)
    xmin, xmax = _final_1d(xlo, xhi, ax.xmin, ax.xmax, 0.05)
    ymin, ymax = _final_1d(ylo, yhi, ax.ymin, ax.ymax, 0.05)
    return xmin, xmax, ymin, ymax
end

# Advance-sum width of a tick label at `size` px — Makie's text_bb width is
# the FULL-ADVANCE sum (oracle-verified: text_bb("0.25", TGH, 14) = 27.244 =
# Σ hadvance·14), not the ink extent. T-004 tables supply the advances.
function _label_advance_width(l::TickLabel, size::Float64)
    t = TableExtents()
    w = 0.0
    for c in l.text
        w += glyph_extent!(t, nothing, Int64(codepoint(c)), Int64(0), Int64(400), Int64(0)).hadvance
    end
    for c in l.sup   # superscript drawn full-size until rich labels land
        w += glyph_extent!(t, nothing, Int64(codepoint(c)), Int64(0), Int64(400), Int64(0)).hadvance
    end
    return w * size
end

function _max_label_width(labels::Vector{TickLabel}, size::Float64)
    w = 0.0
    for l in labels
        lw = _label_advance_width(l, size)
        lw > w && (w = lw)
    end
    return w
end

# Oracle-pinned constant: Makie's measured left protrusion exceeds
# ticksize + ticklabelpad + max advance width by EXACTLY 2.0 px across all
# probed scenes (lines/barplot/heatmap/barneg @ 2026-06-11 oracle run).
const AXIS_TICKLABEL_EXTRA = 2.0

"""
    resolve_axis(ax) -> ResolvedAxis

Limits → ticks (`locateticks`, n_ideal 5) → labels → protrusions.
"""
function resolve_axis(ax::Axis)
    xmin, xmax, ymin, ymax = final_limits(ax)
    # Makie `automatic` = WilkinsonTicks(5, k_min=3) over optimize_ticks
    # (lineaxis.jl:560) — locateticks only serves explicit tick objects
    xticks = wilkinson_ticks_default(xmin, xmax)
    yticks = wilkinson_ticks_default(ymin, ymax)
    xlabels = format_ticks_auto(xticks)
    ylabels = format_ticks_auto(yticks)

    tlsize = THEME_FONTSIZE  # ticklabelsize default == fontsize
    label_h = TEXT_HEIGHT_RATIO * tlsize

    bottom = AXIS_TICKSIZE + AXIS_TICKLABELPAD + label_h
    if !isempty(ax.xlabel)
        bottom += AXIS_LABELPADDING + TEXT_HEIGHT_RATIO * ax.xlabelsize
    end
    left = AXIS_TICKSIZE + AXIS_TICKLABELPAD + _max_label_width(ylabels, tlsize) +
           AXIS_TICKLABEL_EXTRA
    if !isempty(ax.ylabel)
        left += AXIS_LABELPADDING + TEXT_HEIGHT_RATIO * ax.ylabelsize
    end
    top = isempty(ax.title) ? 0.0 : TEXT_HEIGHT_RATIO * ax.titlesize + AXIS_TITLEGAP

    return ResolvedAxis(xmin, xmax, ymin, ymax, xticks, xlabels, yticks, ylabels,
                        Protrusions(left, 0.0, top, bottom))
end

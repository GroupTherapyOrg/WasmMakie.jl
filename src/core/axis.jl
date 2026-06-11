# Axis resolution — limits/autolimits, tick integration, decoration model.
#
# Mirrors Makie's Axis semantics (oracle-pinned): autolimits expand the data
# union by 5% margins per side (xautolimitmargin defaults); empty or
# degenerate spans fall back to (0, 10); user limits (non-NaN Axis fields)
# override. Tick values are `locateticks` (the `automatic` path), labels the
# C-003 formatter.
#
# Protrusions use stand-in text metrics (the RecordingCtx ratios calibrated
# against Makie's reported protrusions) — EXACT extents arrive with the text
# engine (plan T-004); the documented tolerance until then is a few px.

# Makie Axis decoration constants (captured from default attributes)
const AXIS_TICKSIZE = 5.0
const AXIS_TICKLABELPAD = 2.0
const AXIS_LABELPADDING = 3.0
const AXIS_SPINEWIDTH = 1.0
const AXIS_TITLEGAP = 4.0
# stand-in text metrics (calibrated vs Makie-reported protrusions @ 14px)
const TEXT_HEIGHT_RATIO = 1.165   # full line height / fontsize
const TEXT_CHAR_RATIO = 0.7       # avg label char width / fontsize

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

function _max_label_chars(labels::Vector{TickLabel})
    n = 0
    for l in labels
        len = length(l.text) + length(l.sup)
        len > n && (n = len)
    end
    return n
end

"""
    resolve_axis(ax) -> ResolvedAxis

Limits → ticks (`locateticks`, n_ideal 5) → labels → protrusions.
"""
function resolve_axis(ax::Axis)
    xmin, xmax, ymin, ymax = final_limits(ax)
    xticks = locateticks(xmin, xmax, 5)
    yticks = locateticks(ymin, ymax, 5)
    xlabels = format_ticks_auto(xticks)
    ylabels = format_ticks_auto(yticks)

    tlsize = THEME_FONTSIZE  # ticklabelsize default == fontsize
    label_h = TEXT_HEIGHT_RATIO * tlsize

    bottom = AXIS_TICKSIZE + AXIS_TICKLABELPAD + label_h
    if !isempty(ax.xlabel)
        bottom += AXIS_LABELPADDING + TEXT_HEIGHT_RATIO * ax.xlabelsize
    end
    left = AXIS_TICKSIZE + AXIS_TICKLABELPAD +
           TEXT_CHAR_RATIO * tlsize * _max_label_chars(ylabels)
    if !isempty(ax.ylabel)
        left += AXIS_LABELPADDING + TEXT_HEIGHT_RATIO * ax.ylabelsize
    end
    top = isempty(ax.title) ? 0.0 : TEXT_HEIGHT_RATIO * ax.titlesize + AXIS_TITLEGAP

    return ResolvedAxis(xmin, xmax, ymin, ymax, xticks, xlabels, yticks, ylabels,
                        Protrusions(left, 0.0, top, bottom))
end

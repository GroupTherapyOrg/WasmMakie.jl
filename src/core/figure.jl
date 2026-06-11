# The static core's Figure/GridPosition/Axis shells — Makie's user-facing API
# as concrete typed structs (no reactive spine: islands rebuild from scratch).
#
# C-001 scope: construction, defaults, grid placement. The Axis fills out in
# C-008 (limits/ticks/decorations); plot types attach in C-007.

"""
    Axis(figure_position; title = "", xlabel = "", ylabel = "")

A 2D axis. Mirrors `Makie.Axis`'s user API; attributes are concrete typed
fields with Makie's defaults. Limits use NaN sentinels for "automatic".
"""
mutable struct Axis
    row::Int64
    col::Int64
    row2::Int64   # span end (== row for single-cell)
    col2::Int64
    title::String
    xlabel::String
    ylabel::String
    # axis limits — NaN = automatic (computed from data at render)
    xmin::Float64
    xmax::Float64
    ymin::Float64
    ymax::Float64
    titlesize::Float64
    xlabelsize::Float64
    ylabelsize::Float64
    # L-001 decoration attributes (Makie @Block Axis defaults, types.jl)
    subtitle::String
    subtitlesize::Float64     # 16 (@inherit fontsize 16)
    titlegap::Float64         # 4
    subtitlegap::Float64      # 0
    titlealign::Int64         # 0 left, 1 center, 2 right (:center default)
    titlevisible::Bool
    subtitlevisible::Bool
    xlabelvisible::Bool
    ylabelvisible::Bool
    xgridvisible::Bool        # true
    ygridvisible::Bool        # true
    xminorgridvisible::Bool   # false
    yminorgridvisible::Bool   # false
    xminorticksvisible::Bool  # false
    yminorticksvisible::Bool  # false
    xminorticks_n::Int64      # IntervalsBetween(2)
    yminorticks_n::Int64
    xticksvisible::Bool       # true
    yticksvisible::Bool       # true
    xticklabelsvisible::Bool  # true
    yticklabelsvisible::Bool  # true
    leftspinevisible::Bool    # true
    rightspinevisible::Bool
    topspinevisible::Bool
    bottomspinevisible::Bool
    # autolimit margins (Makie x/yautolimitmargin 0.05; heatmap!/image! call
    # the tightlimits! rule — needs_tight_limits — and zero them)
    xautolimitmargin::Float64
    yautolimitmargin::Float64
    # L-002 legend state (axislegend) — drawn inside the axis viewport
    legend_active::Bool
    legend_halign::Int64      # 0 left, 1 center, 2 right
    legend_valign::Int64      # 0 bottom, 1 center, 2 top
    legend_nbanks::Int64
    # typed plot containers (closed-world: one concrete vector per kind,
    # types defined in plots.jl which is included before this file) + order
    lines::Vector{LinesPlot}
    scatters::Vector{ScatterPlot}
    bars::Vector{BarPlotData}
    heatmaps::Vector{HeatmapPlot}
    images::Vector{ImagePlot}
    hvlines::Vector{HVLines}
    hvspans::Vector{HVSpan}
    ablines::Vector{ABLines}
    segments::Vector{SegmentsPlot}
    filledcurves::Vector{FilledCurve}
    bands::Vector{BandPlot}
    polys::Vector{PolyPlot}
    meshes::Vector{MeshPlot}
    plot_order::Vector{Tuple{Int64,Int64}}  # (PLOT_* kind, index)
end

_titlealign_code(s::Symbol) = s === :left ? Int64(0) : s === :right ? Int64(2) : Int64(1)

function Axis(; title::String = "", xlabel::String = "", ylabel::String = "",
              subtitle::String = "", titlealign::Symbol = :center)
    return Axis(1, 1, 1, 1, title, xlabel, ylabel,
                NaN, NaN, NaN, NaN,
                THEME_FONTSIZE,  # titlesize @inherit(:fontsize) — theme 14, NOT the 16 fallback
                THEME_FONTSIZE, THEME_FONTSIZE,
                subtitle, THEME_FONTSIZE, 4.0, 0.0, _titlealign_code(titlealign),
                true, true, true, true,
                true, true, false, false, false, false,
                2, 2,
                true, true, true, true,
                true, true, true, true,
                0.05, 0.05,
                false, 2, 2, 1,
                LinesPlot[], ScatterPlot[], BarPlotData[], HeatmapPlot[],
                ImagePlot[], HVLines[], HVSpan[], ABLines[], SegmentsPlot[],
                FilledCurve[], BandPlot[], PolyPlot[], MeshPlot[],
                Tuple{Int64,Int64}[])
end

"""
    axislegend(ax; position = :rt, nbanks = 1)

Add a legend inside the axis (Makie parity): entries are the axis plots with
nonempty `label`s, in plot order. `position` is the 2-letter halign/valign
symbol (`:lt`, `:rt`, `:lb`, `:rb`, `:ct`, …).
"""
function axislegend(ax::Axis; position::Symbol = :rt, nbanks::Integer = 1)
    # WTGAP: string(::Symbol) + char indexing trap in wasm — direct Symbol
    # comparisons over the 9 two-letter positions instead
    ax.legend_halign = (position === :lt || position === :lc || position === :lb) ? Int64(0) :
                       (position === :ct || position === :cc || position === :cb) ? Int64(1) : Int64(2)
    ax.legend_valign = (position === :lb || position === :cb || position === :rb) ? Int64(0) :
                       (position === :lc || position === :cc || position === :rc) ? Int64(1) : Int64(2)
    ax.legend_nbanks = Int64(nbanks)
    ax.legend_active = true
    return ax
end

"""
    Colorbar(figure_position; limits = (0, 1), label = "", vertical = true)
    Colorbar(figure_position, hm::HeatmapPlot; label = "", vertical = true)

A continuous colorbar grid cell (L-003, viridis — the core's colormap).
The plot-linked form takes its range from the heatmap's colorrange (or its
data extrema when automatic). Vertical bars tick to the right (Makie
flipaxis default).
"""
mutable struct Colorbar
    row::Int64
    col::Int64
    row2::Int64
    col2::Int64
    lo::Float64
    hi::Float64
    label::String
    vertical::Bool
end

"""
    Figure(; size = $(THEME_SIZE), backgroundcolor = white, figure_padding = $(THEME_FIGURE_PADDING))

The top-level figure. `fig[row, col]` returns a `GridPosition` that `Axis`
constructors attach to, mirroring Makie's API.
"""
mutable struct Figure
    width::Float64
    height::Float64
    backgroundcolor::NTuple{4,Float64}
    padding::Float64
    rowgap::Float64
    colgap::Float64
    axes::Vector{Axis}
    colorbars::Vector{Colorbar}
    rowsizes::Vector{SizeSpec}   # sparse overrides via rowsize!; auto beyond length
    colsizes::Vector{SizeSpec}
end

function Figure(; size::Tuple{Real,Real} = THEME_SIZE,
                backgroundcolor::NTuple{4,Float64} = THEME_BACKGROUNDCOLOR,
                figure_padding::Real = THEME_FIGURE_PADDING)
    return Figure(Float64(size[1]), Float64(size[2]), backgroundcolor,
                  Float64(figure_padding), THEME_ROWGAP, THEME_COLGAP, Axis[],
                  Colorbar[], SizeSpec[], SizeSpec[])
end

struct GridPosition
    figure::Figure
    row::Int64
    col::Int64
    row2::Int64   # span end
    col2::Int64
end

Base.getindex(fig::Figure, row::Integer, col::Integer) =
    GridPosition(fig, Int64(row), Int64(col), Int64(row), Int64(col))
Base.getindex(fig::Figure, row::Integer, cols::UnitRange{<:Integer}) =
    GridPosition(fig, Int64(row), Int64(first(cols)), Int64(row), Int64(last(cols)))
Base.getindex(fig::Figure, rows::UnitRange{<:Integer}, col::Integer) =
    GridPosition(fig, Int64(first(rows)), Int64(col), Int64(last(rows)), Int64(col))
Base.getindex(fig::Figure, rows::UnitRange{<:Integer}, cols::UnitRange{<:Integer}) =
    GridPosition(fig, Int64(first(rows)), Int64(first(cols)), Int64(last(rows)), Int64(last(cols)))

"""
    Relative(f) / Fixed(px) / Auto()

GridLayoutBase's content sizes (L-004) for `colsize!`/`rowsize!`.
"""
Relative(f::Real) = relative_size(Float64(f))
Fixed(px::Real) = fixed_size(Float64(px))
Auto() = auto_size()

"Set column `i`'s size (SizeSpec or px number) — Makie colsize! parity."
function colsize!(fig::Figure, i::Integer, sz::SizeSpec)
    while length(fig.colsizes) < i
        push!(fig.colsizes, auto_size())
    end
    fig.colsizes[i] = sz
    return fig
end
colsize!(fig::Figure, i::Integer, px::Real) = colsize!(fig, i, fixed_size(Float64(px)))

"Set row `i`'s size — Makie rowsize! parity."
function rowsize!(fig::Figure, i::Integer, sz::SizeSpec)
    while length(fig.rowsizes) < i
        push!(fig.rowsizes, auto_size())
    end
    fig.rowsizes[i] = sz
    return fig
end
rowsize!(fig::Figure, i::Integer, px::Real) = rowsize!(fig, i, fixed_size(Float64(px)))

function Colorbar(gp::GridPosition; limits::Tuple{Real,Real} = (0.0, 1.0),
                  label::String = "", vertical::Bool = true)
    cb = Colorbar(gp.row, gp.col, gp.row2, gp.col2,
                  Float64(limits[1]), Float64(limits[2]), label, vertical)
    push!(gp.figure.colorbars, cb)
    return cb
end

function Colorbar(gp::GridPosition, hm::HeatmapPlot; label::String = "",
                  vertical::Bool = true)
    lo = isnan(hm.colorrange_min) ? minimum(hm.values) : hm.colorrange_min
    hi = isnan(hm.colorrange_max) ? maximum(hm.values) : hm.colorrange_max
    cb = Colorbar(gp.row, gp.col, gp.row2, gp.col2, lo, hi, label, vertical)
    push!(gp.figure.colorbars, cb)
    return cb
end

"""
    hidexdecorations!(ax; label = true, ticklabels = true, ticks = true,
                      grid = true, minorgrid = true, minorticks = true)

Hide x-axis decorations (Makie parity; flags select which).
"""
function hidexdecorations!(ax::Axis; label::Bool = true, ticklabels::Bool = true,
                           ticks::Bool = true, grid::Bool = true,
                           minorgrid::Bool = true, minorticks::Bool = true)
    label && (ax.xlabelvisible = false)
    ticklabels && (ax.xticklabelsvisible = false)
    ticks && (ax.xticksvisible = false)
    grid && (ax.xgridvisible = false)
    minorgrid && (ax.xminorgridvisible = false)
    minorticks && (ax.xminorticksvisible = false)
    return ax
end

"Hide y-axis decorations (Makie parity; flags select which)."
function hideydecorations!(ax::Axis; label::Bool = true, ticklabels::Bool = true,
                           ticks::Bool = true, grid::Bool = true,
                           minorgrid::Bool = true, minorticks::Bool = true)
    label && (ax.ylabelvisible = false)
    ticklabels && (ax.yticklabelsvisible = false)
    ticks && (ax.yticksvisible = false)
    grid && (ax.ygridvisible = false)
    minorgrid && (ax.yminorgridvisible = false)
    minorticks && (ax.yminorticksvisible = false)
    return ax
end

"Hide x and y decorations (the title is NOT hidden — Makie parity)."
function hidedecorations!(ax::Axis; label::Bool = true, ticklabels::Bool = true,
                          ticks::Bool = true, grid::Bool = true,
                          minorgrid::Bool = true, minorticks::Bool = true)
    hidexdecorations!(ax; label, ticklabels, ticks, grid, minorgrid, minorticks)
    hideydecorations!(ax; label, ticklabels, ticks, grid, minorgrid, minorticks)
    return ax
end

"""
    hidespines!(ax, spines::Symbol... = :l, :r, :t, :b)

Hide axis spines (`:l`eft, `:r`ight, `:t`op, `:b`ottom — Makie parity).
"""
function hidespines!(ax::Axis, spines::Symbol...)
    sps = isempty(spines) ? (:l, :r, :t, :b) : spines
    for s in sps
        s === :l && (ax.leftspinevisible = false)
        s === :r && (ax.rightspinevisible = false)
        s === :t && (ax.topspinevisible = false)
        s === :b && (ax.bottomspinevisible = false)
    end
    return ax
end

function Axis(gp::GridPosition; kwargs...)
    ax = Axis(; kwargs...)
    ax.row = gp.row
    ax.col = gp.col
    ax.row2 = gp.row2
    ax.col2 = gp.col2
    push!(gp.figure.axes, ax)
    return ax
end

"Grid extents: (nrows, ncols) spanned by the figure's axes (≥1×1)."
function grid_extents(fig::Figure)
    nrows = Int64(1)
    ncols = Int64(1)
    for ax in fig.axes
        ax.row2 > nrows && (nrows = ax.row2)
        ax.col2 > ncols && (ncols = ax.col2)
    end
    for cb in fig.colorbars
        cb.row2 > nrows && (nrows = cb.row2)
        cb.col2 > ncols && (ncols = cb.col2)
    end
    return nrows, ncols
end

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
    # typed plot containers (closed-world: one concrete vector per kind,
    # types defined in plots.jl which is included before this file) + order
    lines::Vector{LinesPlot}
    scatters::Vector{ScatterPlot}
    bars::Vector{BarPlotData}
    heatmaps::Vector{HeatmapPlot}
    images::Vector{ImagePlot}
    plot_order::Vector{Tuple{Int64,Int64}}  # (PLOT_* kind, index)
end

_titlealign_code(s::Symbol) = s === :left ? Int64(0) : s === :right ? Int64(2) : Int64(1)

function Axis(; title::String = "", xlabel::String = "", ylabel::String = "",
              subtitle::String = "", titlealign::Symbol = :center)
    return Axis(1, 1, title, xlabel, ylabel,
                NaN, NaN, NaN, NaN,
                THEME_FONTSIZE,  # titlesize @inherit(:fontsize) — theme 14, NOT the 16 fallback
                THEME_FONTSIZE, THEME_FONTSIZE,
                subtitle, THEME_FONTSIZE, 4.0, 0.0, _titlealign_code(titlealign),
                true, true, true, true,
                true, true, false, false, false, false,
                2, 2,
                true, true, true, true,
                true, true, true, true,
                LinesPlot[], ScatterPlot[], BarPlotData[], HeatmapPlot[],
                ImagePlot[], Tuple{Int64,Int64}[])
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
end

function Figure(; size::Tuple{Real,Real} = THEME_SIZE,
                backgroundcolor::NTuple{4,Float64} = THEME_BACKGROUNDCOLOR,
                figure_padding::Real = THEME_FIGURE_PADDING)
    return Figure(Float64(size[1]), Float64(size[2]), backgroundcolor,
                  Float64(figure_padding), THEME_ROWGAP, THEME_COLGAP, Axis[])
end

struct GridPosition
    figure::Figure
    row::Int64
    col::Int64
end

Base.getindex(fig::Figure, row::Integer, col::Integer) =
    GridPosition(fig, Int64(row), Int64(col))

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
    push!(gp.figure.axes, ax)
    return ax
end

"Grid extents: (nrows, ncols) spanned by the figure's axes (≥1×1)."
function grid_extents(fig::Figure)
    nrows = Int64(1)
    ncols = Int64(1)
    for ax in fig.axes
        ax.row > nrows && (nrows = ax.row)
        ax.col > ncols && (ncols = ax.col)
    end
    return nrows, ncols
end

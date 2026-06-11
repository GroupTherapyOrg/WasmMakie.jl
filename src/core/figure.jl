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
end

function Axis(; title::String = "", xlabel::String = "", ylabel::String = "")
    return Axis(1, 1, title, xlabel, ylabel,
                NaN, NaN, NaN, NaN,
                16.0,  # Makie Axis titlesize default (@inherit titlesize 16f0)
                THEME_FONTSIZE, THEME_FONTSIZE)
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

# The static core's plot types + plotting API — Makie's user-facing functions
# (`lines!`, `scatter!`, `barplot!`, `heatmap!`, `image!`) over concrete typed
# structs with Makie's defaults (captured from default_theme: barplot gap 0.2,
# strokewidths 0, linestyle solid). No reactive spine: plot calls append data,
# render walks it.

const PLOT_LINES = Int64(1)
const PLOT_SCATTER = Int64(2)
const PLOT_BARPLOT = Int64(3)
const PLOT_HEATMAP = Int64(4)
const PLOT_IMAGE = Int64(5)
const PLOT_HVLINES = Int64(6)
const PLOT_HVSPAN = Int64(7)
const PLOT_ABLINES = Int64(8)
const PLOT_SEGMENTS = Int64(9)
const PLOT_FILLEDCURVE = Int64(10)
const PLOT_BAND = Int64(11)
const PLOT_POLY = Int64(12)

# linestyles in Makie's encoding (vendor/ticks of lines draw layer consume these)
const LINESTYLE_SOLID = Int64(0)
const LINESTYLE_DASH = Int64(1)
const LINESTYLE_DOT = Int64(2)
const LINESTYLE_DASHDOT = Int64(3)

# markers (subset; grows with the corpus)
const MARKER_CIRCLE = Int64(0)
const MARKER_RECT = Int64(1)
const MARKER_UTRIANGLE = Int64(2)

mutable struct LinesPlot
    x::Vector{Float64}
    y::Vector{Float64}
    color::NTuple{4,Float64}
    linewidth::Float64
    linestyle::Int64
    label::String          # legend entry ("" = none)
end

mutable struct ScatterPlot
    x::Vector{Float64}
    y::Vector{Float64}
    color::NTuple{4,Float64}
    markersize::Float64
    marker::Int64
    strokecolor::NTuple{4,Float64}
    strokewidth::Float64
    label::String
end

mutable struct BarPlotData
    x::Vector{Float64}
    y::Vector{Float64}
    color::NTuple{4,Float64}
    gap::Float64
    strokecolor::NTuple{4,Float64}
    strokewidth::Float64
    label::String
    width::Float64   # drawn bar width in DATA units: (1−gap)·min-step (Makie automatic)
    fillto::Vector{Float64}              # per-bar baseline (empty = 0; stack/waterfall)
    colors::Vector{NTuple{4,Float64}}    # per-bar colors (empty = uniform .color)
end

# R-002 wave-1 annotation plots (Makie basic_recipes: hvlines, hvspan,
# ablines, linesegments — LineSegments/Poly attribute sets, color cycled)
mutable struct HVLines
    horizontal::Bool         # hlines! vs vlines!
    values::Vector{Float64}  # data coords in the line's own dimension
    color::NTuple{4,Float64}
    linewidth::Float64
    linestyle::Int64
    label::String
end

mutable struct HVSpan
    horizontal::Bool         # hspan! vs vspan!
    los::Vector{Float64}
    his::Vector{Float64}
    color::NTuple{4,Float64}
    label::String
end

mutable struct ABLines
    intercepts::Vector{Float64}
    slopes::Vector{Float64}
    color::NTuple{4,Float64}
    linewidth::Float64
    linestyle::Int64
    label::String
end

mutable struct SegmentsPlot
    x::Vector{Float64}       # consecutive pairs form segments
    y::Vector{Float64}
    color::NTuple{4,Float64}
    linewidth::Float64
    linestyle::Int64
    label::String
end

# filled curve down to a baseline (density!, future band!) — Poly attrs
mutable struct FilledCurve
    x::Vector{Float64}
    y::Vector{Float64}
    baseline::Float64
    color::NTuple{4,Float64}
    strokecolor::NTuple{4,Float64}
    strokewidth::Float64
    label::String
end

# band between two curves (band!, violin/density internals) — Poly attrs
mutable struct BandPlot
    x::Vector{Float64}
    ylow::Vector{Float64}
    yhigh::Vector{Float64}
    color::NTuple{4,Float64}
    label::String
end

# generic filled polygon(s) in data space (pie sectors, violin bodies,
# boxplot boxes; future poly!) — flat ring-list representation
mutable struct PolyPlot
    ring_starts::Vector{Int64}   # 1-based start index per ring
    xs::Vector{Float64}          # all ring vertices, concatenated
    ys::Vector{Float64}
    color::NTuple{4,Float64}
    strokecolor::NTuple{4,Float64}
    strokewidth::Float64
    label::String
end

# WTGAP(3aaa51b9a688): Matrix{Float64} fails wasm validation (struct.new
# ref-type mismatch) — values stored column-major flat, like ImagePlot.
mutable struct HeatmapPlot
    xs::Vector{Float64}      # nx+1 edges
    ys::Vector{Float64}      # ny+1 edges
    values::Vector{Float64}  # column-major flat (i + (j-1)*nx)
    nx::Int64
    ny::Int64
    colorrange_min::Float64  # NaN = automatic
    colorrange_max::Float64
end

mutable struct ImagePlot
    x0::Float64
    x1::Float64
    y0::Float64
    y1::Float64
    pixels::Vector{NTuple{4,Float64}}  # column-major flat (i + (j-1)*ni)
    ni::Int64
    nj::Int64
    interpolate::Bool
end

"Named colors the API accepts as Symbols (CSS values, matching Makie.to_color)."
function named_color(s::Symbol)::NTuple{4,Float64}
    s === :black && return (0.0, 0.0, 0.0, 1.0)
    s === :white && return (1.0, 1.0, 1.0, 1.0)
    s === :red && return (1.0, 0.0, 0.0, 1.0)
    s === :green && return (0.0, 128.0 / 255.0, 0.0, 1.0)
    s === :blue && return (0.0, 0.0, 1.0, 1.0)
    s === :orange && return (1.0, 165.0 / 255.0, 0.0, 1.0)
    s === :purple && return (128.0 / 255.0, 0.0, 128.0 / 255.0, 1.0)
    s === :gray && return (128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 1.0)
    s === :grey && return (128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 1.0)
    s === :cyan && return (0.0, 1.0, 1.0, 1.0)
    s === :magenta && return (1.0, 0.0, 1.0, 1.0)
    s === :yellow && return (1.0, 1.0, 0.0, 1.0)
    s === :transparent && return (0.0, 0.0, 0.0, 0.0)
    error("WasmMakie: unknown named color :$s — pass an (r, g, b, a) tuple")
end

_color(c::NTuple{4,Float64}) = c
_color(c::Symbol) = named_color(c)

_f64vec(v::Vector{Float64}) = v
_f64vec(v::AbstractVector{<:Real}) = Float64[Float64(x) for x in v]

_linestyle(s::Symbol)::Int64 =
    s === :solid ? LINESTYLE_SOLID :
    s === :dash ? LINESTYLE_DASH :
    s === :dot ? LINESTYLE_DOT :
    s === :dashdot ? LINESTYLE_DASHDOT :
    error("WasmMakie: unsupported linestyle :$s")

_marker(s::Symbol)::Int64 =
    s === :circle ? MARKER_CIRCLE :
    s === :rect ? MARKER_RECT :
    s === :utriangle ? MARKER_UTRIANGLE :
    error("WasmMakie: unsupported marker :$s")


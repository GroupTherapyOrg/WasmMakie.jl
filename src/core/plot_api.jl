# The plotting API — Makie's user-facing functions over the typed plot
# structs (defined in plots.jl, before Axis so its containers are concrete).

# next color in the Wong cycle for this axis (Makie's per-axis plot cycling)
_next_cycle_color(ax::Axis) = cycle_color(length(ax.plot_order) + 1)

function _push_plot!(ax::Axis, kind::Int64, idx::Int64)
    push!(ax.plot_order, (kind, idx))
    return nothing
end

"""
    lines!(ax, x, y; color = <cycle>, linewidth = 1.5, linestyle = :solid)

Makie's `lines!` over the static core. `x` may be any real vector or range;
`y` may be a vector or a function applied to `x`.
"""
function lines!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
                color = nothing, linewidth::Real = THEME_LINEWIDTH,
                linestyle::Symbol = :solid, label::String = "")
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    push!(ax.lines, LinesPlot(_f64vec(x), _f64vec(y), c, Float64(linewidth), _linestyle(linestyle), label))
    _push_plot!(ax, PLOT_LINES, Int64(length(ax.lines)))
    return ax.lines[end]
end

lines!(ax::Axis, x::AbstractVector{<:Real}, f::Function; kwargs...) =
    lines!(ax, x, Float64[Float64(f(v)) for v in x]; kwargs...)

"""
    scatter!(ax, x, y; color = <cycle>, markersize = 9, marker = :circle, …)
"""
function scatter!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
                  color = nothing, markersize::Real = THEME_MARKERSIZE,
                  marker::Symbol = :circle, strokecolor = :black,
                  strokewidth::Real = 0.0, label::String = "")
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    push!(ax.scatters, ScatterPlot(_f64vec(x), _f64vec(y), c, Float64(markersize),
                                   _marker(marker), _color(strokecolor), Float64(strokewidth), label))
    _push_plot!(ax, PLOT_SCATTER, Int64(length(ax.scatters)))
    return ax.scatters[end]
end

"""
    barplot!(ax, x, y; color = <cycle>, gap = 0.2, …)
"""
function barplot!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
                  color = nothing, gap::Real = 0.2, strokecolor = :black,
                  strokewidth::Real = 0.0, label::String = "")
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    push!(ax.bars, BarPlotData(_f64vec(x), _f64vec(y), c, Float64(gap),
                               _color(strokecolor), Float64(strokewidth), label))
    _push_plot!(ax, PLOT_BARPLOT, Int64(length(ax.bars)))
    return ax.bars[end]
end

"""
    heatmap!(ax, xs, ys, values; colorrange = automatic)

`xs`/`ys` are cell edges (length nx+1/ny+1, Makie's explicit-edge form) or
centers (length nx/ny — converted to edges like Makie's heatmap transform).
"""
function heatmap!(ax::Axis, xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real},
                  values::AbstractMatrix{<:Real};
                  colorrange::Tuple{Real,Real} = (NaN, NaN))
    nx, ny = size(values)
    exs = _f64vec(xs)
    eys = _f64vec(ys)
    length(exs) == nx && (exs = _centers_to_edges(exs))
    length(eys) == ny && (eys = _centers_to_edges(eys))
    length(exs) == nx + 1 || error("heatmap: xs must have length $(nx) (centers) or $(nx + 1) (edges)")
    length(eys) == ny + 1 || error("heatmap: ys must have length $(ny) (centers) or $(ny + 1) (edges)")
    vals = Vector{Float64}(undef, nx * ny)
    for j in 1:ny, i in 1:nx
        vals[i + (j - 1) * nx] = Float64(values[i, j])
    end
    push!(ax.heatmaps, HeatmapPlot(exs, eys, vals, Int64(nx), Int64(ny),
                                   Float64(colorrange[1]), Float64(colorrange[2])))
    _push_plot!(ax, PLOT_HEATMAP, Int64(length(ax.heatmaps)))
    return ax.heatmaps[end]
end

heatmap!(ax::Axis, values::AbstractMatrix{<:Real}; kwargs...) =
    heatmap!(ax, 1:size(values, 1), 1:size(values, 2), values; kwargs...)

# WTGAP(3aaa51b9a688): Matrix construction is unavailable inside wasm-compiled
# figure kernels — flat column-major Vector overload for those callers. Same
# drawing semantics as the Matrix method (which remains the host-facing API).
function heatmap!(ax::Axis, xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real},
                  values::AbstractVector{<:Real}, nx::Int64, ny::Int64;
                  colorrange::Tuple{Real,Real} = (NaN, NaN))
    length(values) == nx * ny || error("heatmap: flat values must have length nx*ny")
    exs = _f64vec(xs)
    eys = _f64vec(ys)
    length(exs) == nx && (exs = _centers_to_edges(exs))
    length(eys) == ny && (eys = _centers_to_edges(eys))
    length(exs) == nx + 1 || error("heatmap: xs must have length $(nx) (centers) or $(nx + 1) (edges)")
    length(eys) == ny + 1 || error("heatmap: ys must have length $(ny) (centers) or $(ny + 1) (edges)")
    vals = Vector{Float64}(undef, nx * ny)
    for k in 1:(nx * ny)
        vals[k] = Float64(values[k])
    end
    push!(ax.heatmaps, HeatmapPlot(exs, eys, vals, nx, ny,
                                   Float64(colorrange[1]), Float64(colorrange[2])))
    _push_plot!(ax, PLOT_HEATMAP, Int64(length(ax.heatmaps)))
    return ax.heatmaps[end]
end

# Makie's heatmap center→edge expansion (midpoints, extrapolated ends)
function _centers_to_edges(cs::Vector{Float64})
    n = length(cs)
    n == 1 && return [cs[1] - 0.5, cs[1] + 0.5]
    edges = Vector{Float64}(undef, n + 1)
    for i in 2:n
        edges[i] = 0.5 * (cs[i - 1] + cs[i])
    end
    edges[1] = cs[1] - 0.5 * (cs[2] - cs[1])
    edges[n + 1] = cs[n] + 0.5 * (cs[n] - cs[n - 1])
    return edges
end

"""
    image!(ax, xspan, yspan, pixels; interpolate = true)

`pixels` is a matrix of `(r, g, b, a)` tuples (or any `AbstractMatrix` of
4-tuples in 0–1); spans are `(lo, hi)` tuples.
"""
function image!(ax::Axis, xspan::Tuple{Real,Real}, yspan::Tuple{Real,Real},
                pixels::AbstractMatrix{NTuple{4,Float64}}; interpolate::Bool = true)
    ni, nj = size(pixels)
    flat = Vector{NTuple{4,Float64}}(undef, ni * nj)
    for j in 1:nj, i in 1:ni
        flat[i + (j - 1) * ni] = pixels[i, j]
    end
    push!(ax.images, ImagePlot(Float64(xspan[1]), Float64(xspan[2]),
                               Float64(yspan[1]), Float64(yspan[2]),
                               flat, Int64(ni), Int64(nj), interpolate))
    _push_plot!(ax, PLOT_IMAGE, Int64(length(ax.images)))
    return ax.images[end]
end

# WTGAP(a9bf645b1003): Matrix{NTuple{4,Float64}} literals trap in wasm —
# flat column-major Vector overload for wasm-compiled figure kernels.
function image!(ax::Axis, xspan::Tuple{Real,Real}, yspan::Tuple{Real,Real},
                pixels::AbstractVector{NTuple{4,Float64}}, ni::Int64, nj::Int64;
                interpolate::Bool = true)
    length(pixels) == ni * nj || error("image: flat pixels must have length ni*nj")
    flat = Vector{NTuple{4,Float64}}(undef, ni * nj)
    for k in 1:(ni * nj)
        flat[k] = pixels[k]
    end
    push!(ax.images, ImagePlot(Float64(xspan[1]), Float64(xspan[2]),
                               Float64(yspan[1]), Float64(yspan[2]),
                               flat, ni, nj, interpolate))
    _push_plot!(ax, PLOT_IMAGE, Int64(length(ax.images)))
    return ax.images[end]
end

# ── data limits (consumed by C-008 autolimits) ──────────────────────────
function _extrema_finite(v::Vector{Float64})
    lo = Inf
    hi = -Inf
    for x in v
        isfinite(x) || continue
        x < lo && (lo = x)
        x > hi && (hi = x)
    end
    return lo, hi
end

data_limits(p::LinesPlot) = (_extrema_finite(p.x)..., _extrema_finite(p.y)...)
data_limits(p::ScatterPlot) = (_extrema_finite(p.x)..., _extrema_finite(p.y)...)
function data_limits(p::BarPlotData)
    xlo, xhi = _extrema_finite(p.x)
    ylo, yhi = _extrema_finite(p.y)
    # bars reach down/up to 0 (Makie barplot fillto default)
    return (xlo, xhi, min(ylo, 0.0), max(yhi, 0.0))
end
data_limits(p::HeatmapPlot) = (p.xs[1], p.xs[end], p.ys[1], p.ys[end])
data_limits(p::ImagePlot) = (p.x0, p.x1, p.y0, p.y1)

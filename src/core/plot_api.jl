# The plotting API — Makie's user-facing functions over the typed plot
# structs (defined in plots.jl, before Axis so its containers are concrete).

"Makie tightlimits!: zero the autolimit margins (heatmap/image plots)."
function _tightlimits!(ax::Axis)
    ax.xautolimitmargin = 0.0
    ax.yautolimitmargin = 0.0
    return nothing
end

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

"min positive difference between the UNIQUE sorted values (Makie automatic width base)"
function _min_unique_step(xs::Vector{Float64})
    uniq = Float64[]
    for v in xs
        found = false
        for u in uniq
            v == u && (found = true; break)
        end
        found || push!(uniq, v)
    end
    sort!(uniq)
    length(uniq) > 1 || return 1.0
    step = Inf
    for i in 2:length(uniq)
        d = uniq[i] - uniq[i - 1]
        d > 0.0 && d < step && (step = d)
    end
    return isfinite(step) ? step : 1.0
end

"""
    barplot!(ax, x, y; color = <cycle or per-bar vector>, gap = 0.2,
             dodge = <Int group ids>, stack = <Int stack ids>, …)
"""
function barplot!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
                  color = nothing, gap::Real = 0.2, strokecolor = :black,
                  strokewidth::Real = 0.0, label::String = "",
                  dodge::AbstractVector{<:Integer} = Int64[], n_dodge::Integer = 0,
                  dodge_gap::Real = 0.03, stack::AbstractVector{<:Integer} = Int64[])
    xs = _f64vec(x)
    ys = _f64vec(y)
    # per-bar colors when a vector is passed (grouped bars)
    cols = NTuple{4,Float64}[]
    c = if color === nothing
        _next_cycle_color(ax)
    elseif color isa AbstractVector
        for ci in color
            push!(cols, _color(ci))
        end
        _color(color[1])
    else
        _color(color)
    end
    step = _min_unique_step(xs)
    width = (1.0 - Float64(gap)) * step
    barw = width
    if !isempty(dodge)
        nd = n_dodge > 0 ? Int64(n_dodge) : Int64(maximum(dodge))
        dg = Float64(dodge_gap)
        dw = (1.0 - (Float64(nd) - 1.0) * dg) / Float64(nd)   # Makie scale_width
        for i in eachindex(xs)
            # Makie shift_dodge: (dw−1)/2 + (i−1)·(dw+gap), in width units
            sh = (dw - 1.0) / 2.0 + (Float64(dodge[i]) - 1.0) * (dw + dg)
            xs[i] += width * sh
        end
        barw = width * dw
    end
    fillto = Float64[]
    if !isempty(stack)
        # Makie stack_grouped_from_to: cumsum in stack order per (x, sign)
        fillto = zeros(Float64, length(ys))
        newy = Vector{Float64}(undef, length(ys))
        done = falses(length(ys))
        for i in eachindex(ys)
            done[i] && continue
            # group: same (already dodged) x and same sign
            idxs = Int64[]
            for j in eachindex(ys)
                if !done[j] && xs[j] == xs[i] && (ys[j] >= 0.0) == (ys[i] >= 0.0)
                    push!(idxs, j)
                end
            end
            # ascending stack index order
            for a in eachindex(idxs)
                for b in (a + 1):length(idxs)
                    if stack[idxs[b]] < stack[idxs[a]]
                        idxs[a], idxs[b] = idxs[b], idxs[a]
                    end
                end
            end
            acc = 0.0
            for j in idxs
                fillto[j] = acc
                acc += ys[j]
                newy[j] = acc
                done[j] = true
            end
        end
        ys = newy
    end
    push!(ax.bars, BarPlotData(xs, ys, c, Float64(gap),
                               _color(strokecolor), Float64(strokewidth), label,
                               barw, fillto, cols))
    _push_plot!(ax, PLOT_BARPLOT, Int64(length(ax.bars)))
    return ax.bars[end]
end

"""
    waterfall!(ax, x, y; color = <cycle>)

Cumulative bars: each bar spans the running sum before → after its value.
"""
function waterfall!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
                    color = nothing, label::String = "")
    xs = _f64vec(x)
    ys = _f64vec(y)
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    fillto = Vector{Float64}(undef, length(ys))
    tos = Vector{Float64}(undef, length(ys))
    acc = 0.0
    for i in eachindex(ys)
        fillto[i] = acc
        acc += ys[i]
        tos[i] = acc
    end
    step = _min_unique_step(xs)
    push!(ax.bars, BarPlotData(xs, tos, c, 0.2, (0.0, 0.0, 0.0, 1.0), 0.0, label,
                               0.8 * step, fillto, NTuple{4,Float64}[]))
    _push_plot!(ax, PLOT_BARPLOT, Int64(length(ax.bars)))
    return ax.bars[end]
end

"""
    crossbar!(ax, x, y, ymin, ymax; ...)

Box from `ymin` to `ymax` with a midline at `y` (Makie crossbar).
"""
function crossbar!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real},
                   ymin::AbstractVector{<:Real}, ymax::AbstractVector{<:Real};
                   color = nothing, label::String = "")
    xs = _f64vec(x)
    c = if color === nothing
        cc = _next_cycle_color(ax)
        (cc[1], cc[2], cc[3], 0.8)
    else
        _color(color)
    end
    step = _min_unique_step(xs)
    halfw = 0.4 * step
    mid_x = Float64[]
    mid_y = Float64[]
    for i in eachindex(xs)
        g = xs[i]
        _push_poly!(ax, Float64[g - halfw, g + halfw, g + halfw, g - halfw],
                    Float64[Float64(ymin[i]), Float64(ymin[i]), Float64(ymax[i]), Float64(ymax[i])],
                    c, (0.0, 0.0, 0.0, 1.0), 1.0, label)
        push!(mid_x, g - halfw); push!(mid_y, Float64(y[i]))
        push!(mid_x, g + halfw); push!(mid_y, Float64(y[i]))
    end
    linesegments!(ax, mid_x, mid_y; color = (0.0, 0.0, 0.0, 1.0))
    return ax.polys[end]
end

"""
    series!(ax, curves::AbstractMatrix; ...) / series!(ax, flat, nseries, npoints)

One line per matrix ROW, cycle-colored (Makie series). The flat overload is
the wasm-kernel form (Matrix construction traps — WTGAP 3aaa51b9a688).
"""
function series!(ax::Axis, curves::AbstractMatrix{<:Real}; linewidth::Real = THEME_LINEWIDTH)
    ns, np = size(curves)
    for si in 1:ns
        ys = Vector{Float64}(undef, np)
        for j in 1:np
            ys[j] = Float64(curves[si, j])
        end
        lines!(ax, collect(1.0:Float64(np)), ys; linewidth)
    end
    return ax.lines[end]
end

function series!(ax::Axis, flat::AbstractVector{<:Real}, nseries::Int64, npoints::Int64;
                 linewidth::Real = THEME_LINEWIDTH)
    for si in 1:nseries
        ys = Vector{Float64}(undef, npoints)
        for j in 1:npoints
            ys[j] = Float64(flat[si + (j - 1) * nseries])
        end
        xs = Vector{Float64}(undef, npoints)
        for j in 1:npoints
            xs[j] = Float64(j)
        end
        lines!(ax, xs, ys; linewidth)
    end
    return ax.lines[end]
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
    _tightlimits!(ax)   # needs_tight_limits(::Heatmap) — Makie figureplotting.jl:419
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
    _tightlimits!(ax)   # needs_tight_limits(::Image)
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
    _tightlimits!(ax)   # needs_tight_limits(::Image)
    _push_plot!(ax, PLOT_IMAGE, Int64(length(ax.images)))
    return ax.images[end]
end

"""
    hlines!(ax, ys; color = <cycle>, linewidth = 1.5, linestyle = :solid)

Horizontal lines across the axis at data `ys` (Makie hvlines.jl parity:
LineSegments attributes, color cycled, spans the full x range).
"""
function hlines!(ax::Axis, ys::AbstractVector{<:Real};
                 color = nothing, linewidth::Real = THEME_LINEWIDTH,
                 linestyle::Symbol = :solid, label::String = "")
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    push!(ax.hvlines, HVLines(true, _f64vec(ys), c, Float64(linewidth),
                              _linestyle(linestyle), label))
    _push_plot!(ax, PLOT_HVLINES, Int64(length(ax.hvlines)))
    return ax.hvlines[end]
end
hlines!(ax::Axis, y::Real; kwargs...) = hlines!(ax, [y]; kwargs...)

"Vertical lines across the axis at data `xs`."
function vlines!(ax::Axis, xs::AbstractVector{<:Real};
                 color = nothing, linewidth::Real = THEME_LINEWIDTH,
                 linestyle::Symbol = :solid, label::String = "")
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    push!(ax.hvlines, HVLines(false, _f64vec(xs), c, Float64(linewidth),
                              _linestyle(linestyle), label))
    _push_plot!(ax, PLOT_HVLINES, Int64(length(ax.hvlines)))
    return ax.hvlines[end]
end
vlines!(ax::Axis, x::Real; kwargs...) = vlines!(ax, [x]; kwargs...)

"Horizontal filled bands from `los` to `his` (full x range)."
function hspan!(ax::Axis, los::AbstractVector{<:Real}, his::AbstractVector{<:Real};
                color = nothing, label::String = "")
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    push!(ax.hvspans, HVSpan(true, _f64vec(los), _f64vec(his), c, label))
    _push_plot!(ax, PLOT_HVSPAN, Int64(length(ax.hvspans)))
    return ax.hvspans[end]
end
hspan!(ax::Axis, lo::Real, hi::Real; kwargs...) = hspan!(ax, [lo], [hi]; kwargs...)

"Vertical filled bands from `los` to `his` (full y range)."
function vspan!(ax::Axis, los::AbstractVector{<:Real}, his::AbstractVector{<:Real};
                color = nothing, label::String = "")
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    push!(ax.hvspans, HVSpan(false, _f64vec(los), _f64vec(his), c, label))
    _push_plot!(ax, PLOT_HVSPAN, Int64(length(ax.hvspans)))
    return ax.hvspans[end]
end
vspan!(ax::Axis, lo::Real, hi::Real; kwargs...) = vspan!(ax, [lo], [hi]; kwargs...)

"Lines `y = intercept + slope·x` across the axis (Makie ablines parity)."
function ablines!(ax::Axis, intercepts::AbstractVector{<:Real}, slopes::AbstractVector{<:Real};
                  color = nothing, linewidth::Real = THEME_LINEWIDTH,
                  linestyle::Symbol = :solid, label::String = "")
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    push!(ax.ablines, ABLines(_f64vec(intercepts), _f64vec(slopes), c,
                              Float64(linewidth), _linestyle(linestyle), label))
    _push_plot!(ax, PLOT_ABLINES, Int64(length(ax.ablines)))
    return ax.ablines[end]
end
ablines!(ax::Axis, a::Real, b::Real; kwargs...) = ablines!(ax, [a], [b]; kwargs...)

"Disconnected segments between consecutive point pairs (Makie linesegments)."
function linesegments!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
                       color = nothing, linewidth::Real = THEME_LINEWIDTH,
                       linestyle::Symbol = :solid, label::String = "")
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    push!(ax.segments, SegmentsPlot(_f64vec(x), _f64vec(y), c, Float64(linewidth),
                                    _linestyle(linestyle), label))
    _push_plot!(ax, PLOT_SEGMENTS, Int64(length(ax.segments)))
    return ax.segments[end]
end

"""
    scatterlines!(ax, x, y; ...)

Lines + scatter with shared color (Makie scatterlines: markercolor follows
linecolor) — two plot entries, one call.
"""
function scatterlines!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
                       color = nothing, linewidth::Real = THEME_LINEWIDTH,
                       linestyle::Symbol = :solid, markersize::Real = THEME_MARKERSIZE,
                       marker::Symbol = :circle, label::String = "")
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    l = lines!(ax, x, y; color = c, linewidth, linestyle, label)
    scatter!(ax, x, y; color = c, markersize, marker)
    return l
end

"""
    stairs!(ax, x, y; step = :pre|:post|:center, ...)

Step lines (Makie stairs.jl conversion translated verbatim → lines).
"""
function stairs!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
                 step::Symbol = :pre, color = nothing,
                 linewidth::Real = THEME_LINEWIDTH, linestyle::Symbol = :solid,
                 label::String = "")
    xs = _f64vec(x)
    ys = _f64vec(y)
    n = length(xs)
    sx = Float64[]
    sy = Float64[]
    if n > 0
        push!(sx, xs[1]); push!(sy, ys[1])
        if step === :pre
            for i in 1:(n - 1)
                push!(sx, xs[i]); push!(sy, ys[i + 1])
                push!(sx, xs[i + 1]); push!(sy, ys[i + 1])
            end
        elseif step === :post
            for i in 1:(n - 1)
                push!(sx, xs[i + 1]); push!(sy, ys[i])
                push!(sx, xs[i + 1]); push!(sy, ys[i + 1])
            end
        else  # :center
            for i in 1:(n - 1)
                halfx = 0.5 * (xs[i] + xs[i + 1])
                push!(sx, halfx); push!(sy, ys[i])
                push!(sx, halfx); push!(sy, ys[i + 1])
            end
            push!(sx, xs[n]); push!(sy, ys[n])
        end
    end
    return lines!(ax, sx, sy; color, linewidth, linestyle, label)
end

"""
    hist!(ax, values; bins = 15, color = <cycle>, ...)

Histogram bars (Makie hist.jl: edges = range(min, nextfloat(max), bins+1),
right-open binning, counts; bars touch — width = bin width).
"""
function hist!(ax::Axis, values::AbstractVector{<:Real}; bins::Integer = 15,
               color = nothing, label::String = "")
    vals = _f64vec(values)
    # Makie hist cycles :patchcolor = wong_colors(0.8) — cycle color at α 0.8
    c = if color === nothing
        cc = _next_cycle_color(ax)
        (cc[1], cc[2], cc[3], 0.8)
    else
        _color(color)
    end
    lo = Inf
    hi = -Inf
    for v in vals
        v < lo && (lo = v)
        v > hi && (hi = v)
    end
    if lo == hi
        lo -= 0.5
        hi += 0.5
    else
        hi = nextfloat(hi)
    end
    nb = Int64(bins)
    binw = (hi - lo) / Float64(nb)
    # edge-comparison binning (right-open): division + floor mis-bins edge
    # values by one ulp (0.2 in [0.1,0.2) at binw 0.1) — StatsBase compares
    # against the edge values themselves
    edges = Vector{Float64}(undef, nb + 1)
    for k in 1:(nb + 1)
        edges[k] = lo + (hi - lo) * Float64(k - 1) / Float64(nb)
    end
    counts = zeros(Float64, nb)
    for v in vals
        k = 1
        while k < nb && v >= edges[k + 1]
            k += 1
        end
        edges[k] <= v < edges[k + 1] && (counts[k] += 1.0)
    end
    centers = Vector{Float64}(undef, nb)
    for k in 1:nb
        centers[k] = lo + (Float64(k) - 0.5) * binw
    end
    push!(ax.bars, BarPlotData(centers, counts, c, 0.0,
                               (0.0, 0.0, 0.0, 1.0), 0.0, label, binw,
                               Float64[], NTuple{4,Float64}[]))
    _push_plot!(ax, PLOT_BARPLOT, Int64(length(ax.bars)))
    return ax.bars[end]
end

"""
    errorbars!(ax, x, y, err; ...) / rangebars!(ax, val, lo, hi; ...)

Vertical error whisker segments (whiskerwidth 0 default — Makie parity).
"""
function errorbars!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real},
                    err::AbstractVector{<:Real};
                    color = nothing, linewidth::Real = THEME_LINEWIDTH,
                    label::String = "")
    xs = _f64vec(x); ys = _f64vec(y); es = _f64vec(err)
    sx = Float64[]; sy = Float64[]
    for i in eachindex(xs)
        push!(sx, xs[i]); push!(sy, ys[i] - es[i])
        push!(sx, xs[i]); push!(sy, ys[i] + es[i])
    end
    return linesegments!(ax, sx, sy; color, linewidth, label)
end

function rangebars!(ax::Axis, val::AbstractVector{<:Real}, lo::AbstractVector{<:Real},
                    hi::AbstractVector{<:Real};
                    color = nothing, linewidth::Real = THEME_LINEWIDTH,
                    label::String = "")
    vs = _f64vec(val); ls = _f64vec(lo); hs = _f64vec(hi)
    sx = Float64[]; sy = Float64[]
    for i in eachindex(vs)
        push!(sx, vs[i]); push!(sy, ls[i])
        push!(sx, vs[i]); push!(sy, hs[i])
    end
    return linesegments!(ax, sx, sy; color, linewidth, label)
end

"""
    stem!(ax, x, y; offset = 0, ...)

Stems from `offset` to `y` with marker heads + trunk line (Makie stem.jl).
"""
function stem!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
               offset::Real = 0, color = nothing, linewidth::Real = THEME_LINEWIDTH,
               markersize::Real = THEME_MARKERSIZE, label::String = "")
    xs = _f64vec(x); ys = _f64vec(y)
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    off = Float64(offset)
    # trunk (linecolor black default upstream; we follow the stem color group)
    lines!(ax, [minimum(xs), maximum(xs)], [off, off];
           color = (0.0, 0.0, 0.0, 1.0), linewidth)
    sx = Float64[]; sy = Float64[]
    for i in eachindex(xs)
        push!(sx, xs[i]); push!(sy, off)
        push!(sx, xs[i]); push!(sy, ys[i])
    end
    linesegments!(ax, sx, sy; color = c, linewidth, label)
    scatter!(ax, xs, ys; color = c, markersize)
    return ax.segments[end]
end

"""
    density!(ax, values; npoints = 200, color, strokecolor, strokewidth)

Filled KDE curve (vendored Gaussian KDE: Silverman bandwidth, ±4bw
boundary — KernelDensity.jl defaults; direct evaluation, not FFT-binned).
"""
function density!(ax::Axis, values::AbstractVector{<:Real}; npoints::Integer = 200,
                  color = nothing, strokecolor = :black, strokewidth::Real = 0.0,
                  label::String = "")
    vals = _f64vec(values)
    c = color === nothing ? _next_cycle_color(ax) : _color(color)
    n = length(vals)
    bw = _silverman_bandwidth(vals)
    lo = minimum(vals) - 4.0 * bw
    hi = maximum(vals) + 4.0 * bw
    np = Int64(npoints)
    gx = Vector{Float64}(undef, np)
    gy = Vector{Float64}(undef, np)
    stepw = (hi - lo) / Float64(np - 1)
    inv2bw2 = 1.0 / (2.0 * bw * bw)
    norm = 1.0 / (Float64(n) * bw * sqrt(2.0 * pi))
    for k in 1:np
        gx[k] = lo + Float64(k - 1) * stepw
        acc = 0.0
        for v in vals
            d = gx[k] - v
            acc += exp(-d * d * inv2bw2)
        end
        gy[k] = acc * norm
    end
    push!(ax.filledcurves, FilledCurve(gx, gy, 0.0, c, _color(strokecolor),
                                       Float64(strokewidth), label))
    _push_plot!(ax, PLOT_FILLEDCURVE, Int64(length(ax.filledcurves)))
    return ax.filledcurves[end]
end

"Silverman's rule (KernelDensity.jl default_bandwidth, alpha 0.9)."
function _silverman_bandwidth(vals::Vector{Float64})
    n = length(vals)
    n <= 1 && return 0.9
    m = 0.0
    for v in vals
        m += v
    end
    m /= Float64(n)
    ss = 0.0
    for v in vals
        ss += (v - m) * (v - m)
    end
    sd = sqrt(ss / Float64(n - 1))
    q25 = _quantile7(vals, 0.25)
    q75 = _quantile7(vals, 0.75)
    width = min(sd, (q75 - q25) / 1.34)
    width == 0.0 && (width = sd == 0.0 ? 1.0 : sd)
    return 0.9 * width * Float64(n)^(-0.2)
end

"Type-7 quantile on a copy-sorted vector (matches Statistics.quantile default)."
function _quantile7(vals::Vector{Float64}, p::Float64)
    n = length(vals)
    sorted = Vector{Float64}(undef, n)
    for i in 1:n
        sorted[i] = vals[i]
    end
    sort!(sorted)
    h = (Float64(n) - 1.0) * p + 1.0
    fl = floor(h)
    i = Int64(fl)
    i >= n && return sorted[n]
    return sorted[i] + (h - fl) * (sorted[i + 1] - sorted[i])
end

"""
    band!(ax, x, ylow, yhigh; color = <cycle α0.8>)

Filled band between two curves (Makie band — drawn as a polygon here; the
mesh-based upstream rendering arrives with R-005).
"""
function band!(ax::Axis, x::AbstractVector{<:Real}, ylow::AbstractVector{<:Real},
               yhigh::AbstractVector{<:Real}; color = nothing, label::String = "")
    c = if color === nothing
        cc = _next_cycle_color(ax)
        (cc[1], cc[2], cc[3], 0.8)   # patchcolor cycle
    else
        _color(color)
    end
    push!(ax.bands, BandPlot(_f64vec(x), _f64vec(ylow), _f64vec(yhigh), c, label))
    _push_plot!(ax, PLOT_BAND, Int64(length(ax.bands)))
    return ax.bands[end]
end

"Push one polygon ring (data coords) as a PolyPlot."
function _push_poly!(ax::Axis, xs::Vector{Float64}, ys::Vector{Float64},
                     color::NTuple{4,Float64}, strokecolor::NTuple{4,Float64},
                     strokewidth::Float64, label::String)
    push!(ax.polys, PolyPlot(Int64[1], xs, ys, color, strokecolor, strokewidth, label))
    _push_plot!(ax, PLOT_POLY, Int64(length(ax.polys)))
    return ax.polys[end]
end

"""
    pie!(ax, values; colors = <Wong cycle>, radius = 1, strokecolor = :black,
         strokewidth = 1, vertex_per_deg = 1)

Pie sectors as polygons at the data-space origin (Makie pie.jl semantics:
sectors approximated at `vertex_per_deg` resolution, radius 1 default).
"""
function pie!(ax::Axis, values::AbstractVector{<:Real};
              colors = nothing, radius::Real = 1.0, strokecolor = :black,
              strokewidth::Real = 1.0, vertex_per_deg::Real = 1.0)
    vals = _f64vec(values)
    total = 0.0
    for v in vals
        total += v
    end
    r = Float64(radius)
    sc = _color(strokecolor)
    a0 = 0.0
    for (i, v) in enumerate(vals)
        frac = total == 0.0 ? 0.0 : v / total
        a1 = a0 + frac * 2.0 * pi
        nseg = max(Int64(2), Int64(ceil((a1 - a0) * 180.0 / pi * Float64(vertex_per_deg))))
        xs = Float64[0.0]
        ys = Float64[0.0]
        for k in 0:nseg
            ang = a0 + (a1 - a0) * Float64(k) / Float64(nseg)
            push!(xs, r * cos(ang))
            push!(ys, r * sin(ang))
        end
        c = colors === nothing ? cycle_color(i) : _color(colors[i])
        _push_poly!(ax, xs, ys, c, sc, Float64(strokewidth), "")
        a0 = a1
    end
    return ax.polys[end]
end

"""
    boxplot!(ax, x, y; width = automatic·0.8, range = 1.5, show_outliers = true)

Per-group box (q25–q75), median line, 1.5·IQR whiskers clamped to data,
outlier markers (Makie stats/boxplot.jl semantics).
"""
function boxplot!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
                  color = nothing, range::Real = 1.5, show_outliers::Bool = true,
                  label::String = "")
    xs = _f64vec(x)
    ys = _f64vec(y)
    c = if color === nothing
        cc = _next_cycle_color(ax)
        (cc[1], cc[2], cc[3], 0.8)
    else
        _color(color)
    end
    groups = Float64[]
    for v in xs
        found = false
        for g in groups
            v == g && (found = true; break)
        end
        found || push!(groups, v)
    end
    sort!(groups)
    step = 1.0
    if length(groups) > 1
        step = Inf
        for i in 2:length(groups)
            d = groups[i] - groups[i - 1]
            d > 0.0 && d < step && (step = d)
        end
    end
    boxw = 0.8 * step
    whisk_x = Float64[]
    whisk_y = Float64[]
    out_x = Float64[]
    out_y = Float64[]
    for g in groups
        gy = Float64[]
        for i in eachindex(xs)
            xs[i] == g && push!(gy, ys[i])
        end
        isempty(gy) && continue
        q1 = _quantile7(gy, 0.25)
        q2 = _quantile7(gy, 0.5)
        q3 = _quantile7(gy, 0.75)
        iqr = q3 - q1
        fence_lo = q1 - Float64(range) * iqr
        fence_hi = q3 + Float64(range) * iqr
        wlo = Inf
        whi = -Inf
        for v in gy
            if fence_lo <= v <= fence_hi
                v < wlo && (wlo = v)
                v > whi && (whi = v)
            elseif show_outliers
                push!(out_x, g)
                push!(out_y, v)
            end
        end
        # box ring
        _push_poly!(ax, Float64[g - 0.5 * boxw, g + 0.5 * boxw, g + 0.5 * boxw, g - 0.5 * boxw],
                    Float64[q1, q1, q3, q3], c, (0.0, 0.0, 0.0, 1.0), 1.0, label)
        # median + whiskers as segments
        push!(whisk_x, g - 0.5 * boxw); push!(whisk_y, q2)
        push!(whisk_x, g + 0.5 * boxw); push!(whisk_y, q2)
        push!(whisk_x, g); push!(whisk_y, q3)
        push!(whisk_x, g); push!(whisk_y, whi)
        push!(whisk_x, g); push!(whisk_y, q1)
        push!(whisk_x, g); push!(whisk_y, wlo)
    end
    isempty(whisk_x) || linesegments!(ax, whisk_x, whisk_y; color = (0.0, 0.0, 0.0, 1.0))
    show_outliers && !isempty(out_x) &&
        scatter!(ax, out_x, out_y; color = (0.0, 0.0, 0.0, 1.0), markersize = 6.0)
    return ax.polys[end]
end

"""
    violin!(ax, x, y; width = automatic·0.8, npoints = 200)

Mirrored per-group KDE bodies (Makie stats/violin.jl, side :both).
"""
function violin!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
                 color = nothing, npoints::Integer = 200, label::String = "")
    xs = _f64vec(x)
    ys = _f64vec(y)
    c = if color === nothing
        cc = _next_cycle_color(ax)
        (cc[1], cc[2], cc[3], 0.8)
    else
        _color(color)
    end
    groups = Float64[]
    for v in xs
        found = false
        for g in groups
            v == g && (found = true; break)
        end
        found || push!(groups, v)
    end
    sort!(groups)
    step = 1.0
    if length(groups) > 1
        step = Inf
        for i in 2:length(groups)
            d = groups[i] - groups[i - 1]
            d > 0.0 && d < step && (step = d)
        end
    end
    halfw = 0.4 * step
    np = Int64(npoints)
    # pass 1: per-group KDEs; the width scale is the GLOBAL max density
    # across groups (Makie scale :area default — peakier groups are wider)
    grids = Vector{Vector{Float64}}()
    denss = Vector{Vector{Float64}}()
    gcs = Float64[]
    gmax = 0.0
    for g in groups
        gy = Float64[]
        for i in eachindex(xs)
            xs[i] == g && push!(gy, ys[i])
        end
        length(gy) > 1 || continue
        bw = _silverman_bandwidth(gy)
        lo = minimum(gy) - 4.0 * bw
        hi = maximum(gy) + 4.0 * bw
        stepw = (hi - lo) / Float64(np - 1)
        dens = Vector{Float64}(undef, np)
        grid = Vector{Float64}(undef, np)
        inv2bw2 = 1.0 / (2.0 * bw * bw)
        norm = 1.0 / (Float64(length(gy)) * bw * sqrt(2.0 * pi))
        for k in 1:np
            grid[k] = lo + Float64(k - 1) * stepw
            acc = 0.0
            for v in gy
                d = grid[k] - v
                acc += exp(-d * d * inv2bw2)
            end
            dens[k] = acc * norm
            dens[k] > gmax && (gmax = dens[k])
        end
        push!(grids, grid)
        push!(denss, dens)
        push!(gcs, g)
    end
    gmax == 0.0 && (gmax = 1.0)
    for gi in eachindex(gcs)
        g = gcs[gi]
        grid = grids[gi]
        dens = denss[gi]
        rx = Float64[]
        ry = Float64[]
        for k in 1:np                      # right side up
            push!(rx, g + halfw * dens[k] / gmax)
            push!(ry, grid[k])
        end
        for k in np:-1:1                   # left side down (mirror)
            push!(rx, g - halfw * dens[k] / gmax)
            push!(ry, grid[k])
        end
        _push_poly!(ax, rx, ry, c, (0.0, 0.0, 0.0, 1.0), 1.0, label)
    end
    return ax.polys[end]
end

"""
    contour!(ax, xs, ys, z; levels = 5, linewidth = 1)

Isolines via the vendored Contour.jl marching squares; level colors sampled
from viridis over the z range (Makie contour defaults). The Matrix method is
the host API; the flat overload is the wasm-kernel form.
"""
function contour!(ax::Axis, xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real},
                  z::AbstractMatrix{<:Real}; levels::Integer = 5, linewidth::Real = 1.0)
    nx, ny = size(z)
    flat = Vector{Float64}(undef, nx * ny)
    for j in 1:ny, i in 1:nx
        flat[i + (j - 1) * nx] = Float64(z[i, j])
    end
    return contour!(ax, xs, ys, flat, Int64(nx), Int64(ny); levels, linewidth)
end

function contour!(ax::Axis, xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real},
                  z::AbstractVector{<:Real}, nx::Int64, ny::Int64;
                  levels::Integer = 5, linewidth::Real = 1.0)
    xv = _f64vec(xs)
    yv = _f64vec(ys)
    zv = _f64vec(z)
    zmin = Inf
    zmax = -Inf
    for v in zv
        v < zmin && (zmin = v)
        v > zmax && (zmax = v)
    end
    hs = contourlevels(zmin, zmax, Int64(levels))
    for h in hs
        c = interpolated_getindex(VIRIDIS, h, zmin, zmax)
        for line in contour_lines(xv, yv, zv, nx, ny, h)
            lx = Vector{Float64}(undef, length(line))
            ly = Vector{Float64}(undef, length(line))
            for i in eachindex(line)
                lx[i] = line[i][1]
                ly[i] = line[i][2]
            end
            lines!(ax, lx, ly; color = c, linewidth = Float64(linewidth))
        end
    end
    return ax.lines[end]
end

"""
    contourf!(ax, xs, ys, z; levels = 10)

Filled contour bands. WASM-DIVERGENCE: rendered as a fine-grid heatmap
quantized to the band midpoints (Makie's exact band polygons come from the
Isoband C library — ccall, unavailable in the closed world). Band colors
are exactly the heatmap colormap at the midpoints; boundaries are grid-
quantized at `upsample`× the input resolution.
"""
function contourf!(ax::Axis, xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real},
                   z::AbstractMatrix{<:Real}; levels::Integer = 10, upsample::Integer = 8)
    nx, ny = size(z)
    flat = Vector{Float64}(undef, nx * ny)
    for j in 1:ny, i in 1:nx
        flat[i + (j - 1) * nx] = Float64(z[i, j])
    end
    return contourf!(ax, xs, ys, flat, Int64(nx), Int64(ny); levels, upsample)
end

function contourf!(ax::Axis, xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real},
                   z::AbstractVector{<:Real}, nx::Int64, ny::Int64;
                   levels::Integer = 10, upsample::Integer = 8)
    xv = _f64vec(xs)
    yv = _f64vec(ys)
    zv = _f64vec(z)
    zmin = Inf
    zmax = -Inf
    for v in zv
        v < zmin && (zmin = v)
        v > zmax && (zmax = v)
    end
    nb = Int64(levels)
    bw = (zmax - zmin) / Float64(nb)
    u = Int64(upsample)
    fx = (nx - 1) * u + 1
    fy = (ny - 1) * u + 1
    fine = Vector{Float64}(undef, fx * fy)
    for j in 1:fy
        gy = 1.0 + Float64(j - 1) / Float64(u)
        j0 = Int64(floor(gy))
        j0 >= ny && (j0 = ny - 1)
        ty = gy - Float64(j0)
        for i in 1:fx
            gx = 1.0 + Float64(i - 1) / Float64(u)
            i0 = Int64(floor(gx))
            i0 >= nx && (i0 = nx - 1)
            tx = gx - Float64(i0)
            v00 = zv[i0 + (j0 - 1) * nx]
            v10 = zv[i0 + 1 + (j0 - 1) * nx]
            v01 = zv[i0 + j0 * nx]
            v11 = zv[i0 + 1 + j0 * nx]
            v = (1.0 - tx) * (1.0 - ty) * v00 + tx * (1.0 - ty) * v10 +
                (1.0 - tx) * ty * v01 + tx * ty * v11
            band = Int64(floor((v - zmin) / bw))
            band < 0 && (band = 0)
            band >= nb && (band = nb - 1)
            fine[i + (j - 1) * fx] = zmin + (Float64(band) + 0.5) * bw
        end
    end
    # cell-center grids spanning the data extent
    fxs = Vector{Float64}(undef, fx)
    for i in 1:fx
        fxs[i] = xv[1] + (xv[end] - xv[1]) * Float64(i - 1) / Float64(fx - 1)
    end
    fys = Vector{Float64}(undef, fy)
    for j in 1:fy
        fys[j] = yv[1] + (yv[end] - yv[1]) * Float64(j - 1) / Float64(fy - 1)
    end
    return heatmap!(ax, fxs, fys, fine, fx, fy; colorrange = (zmin, zmax))
end

"""
    mesh!(ax, vx, vy, faces; color = <single or per-vertex vector>)

2D Gouraud mesh: `faces` is a flat vector of 1-based vertex-index triples.
"""
function mesh!(ax::Axis, vx::AbstractVector{<:Real}, vy::AbstractVector{<:Real},
               faces::AbstractVector{<:Integer};
               color = nothing, label::String = "")
    n = length(vx)
    vr = Vector{Float64}(undef, n)
    vg = Vector{Float64}(undef, n)
    vb = Vector{Float64}(undef, n)
    va = Vector{Float64}(undef, n)
    if color isa AbstractVector
        for i in 1:n
            c = _color(color[i])
            vr[i] = c[1]; vg[i] = c[2]; vb[i] = c[3]; va[i] = c[4]
        end
    else
        c = color === nothing ? _next_cycle_color(ax) : _color(color)
        for i in 1:n
            vr[i] = c[1]; vg[i] = c[2]; vb[i] = c[3]; va[i] = c[4]
        end
    end
    fc = Vector{Int64}(undef, length(faces))
    for i in eachindex(faces)
        fc[i] = Int64(faces[i])
    end
    push!(ax.meshes, MeshPlot(_f64vec(vx), _f64vec(vy), zeros(Float64, n),
                              vr, vg, vb, va, fc, label))
    _push_plot!(ax, PLOT_MESH, Int64(length(ax.meshes)))
    return ax.meshes[end]
end

"""
    surface!(ax, xs, ys, z; azimuth = 1.275π, elevation = π/8)

Surface via a basic fixed orthographic camera projected into the 2D axis
(WASM-DIVERGENCE: no Axis3 — full 3D scenes are out of plan scope; the
camera normalizes data to the unit cube like Axis3's stretched aspect).
Vertex colors are viridis over z. Matrix host API + flat wasm overload.
"""
function surface!(ax::Axis, xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real},
                  z::AbstractMatrix{<:Real}; azimuth::Real = 1.275 * pi,
                  elevation::Real = pi / 8)
    nx, ny = size(z)
    flat = Vector{Float64}(undef, nx * ny)
    for j in 1:ny, i in 1:nx
        flat[i + (j - 1) * nx] = Float64(z[i, j])
    end
    return surface!(ax, xs, ys, flat, Int64(nx), Int64(ny); azimuth, elevation)
end

function surface!(ax::Axis, xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real},
                  z::AbstractVector{<:Real}, nx::Int64, ny::Int64;
                  azimuth::Real = 1.275 * pi, elevation::Real = pi / 8)
    xv = _f64vec(xs)
    yv = _f64vec(ys)
    zv = _f64vec(z)
    zmin = Inf
    zmax = -Inf
    for v in zv
        v < zmin && (zmin = v)
        v > zmax && (zmax = v)
    end
    zspan = zmax == zmin ? 1.0 : zmax - zmin
    xspan = xv[end] == xv[1] ? 1.0 : xv[end] - xv[1]
    yspan = yv[end] == yv[1] ? 1.0 : yv[end] - yv[1]
    ca = cos(Float64(azimuth))
    sa = sin(Float64(azimuth))
    ce = cos(Float64(elevation))
    se = sin(Float64(elevation))
    n = nx * ny
    px = Vector{Float64}(undef, n)
    py = Vector{Float64}(undef, n)
    pd = Vector{Float64}(undef, n)
    vr = Vector{Float64}(undef, n)
    vg = Vector{Float64}(undef, n)
    vb = Vector{Float64}(undef, n)
    va = Vector{Float64}(undef, n)
    for j in 1:ny
        for i in 1:nx
            k = i + (j - 1) * nx
            u = (xv[i] - xv[1]) / xspan - 0.5
            v = (yv[j] - yv[1]) / yspan - 0.5
            zn = (zv[k] - zmin) / zspan - 0.5
            rx = ca * u - sa * v
            ry = sa * u + ca * v
            px[k] = rx
            py[k] = se * ry + ce * zn
            pd[k] = ce * ry - se * zn
            c = interpolated_getindex(VIRIDIS, zv[k], zmin, zmax)
            vr[k] = c[1]; vg[k] = c[2]; vb[k] = c[3]; va[k] = c[4]
        end
    end
    faces = Int64[]
    for j in 1:(ny - 1)
        for i in 1:(nx - 1)
            a = i + (j - 1) * nx
            b = a + 1
            cidx = a + nx
            d = b + nx
            push!(faces, a); push!(faces, b); push!(faces, d)
            push!(faces, a); push!(faces, d); push!(faces, cidx)
        end
    end
    push!(ax.meshes, MeshPlot(px, py, pd, vr, vg, vb, va, faces, ""))
    _push_plot!(ax, PLOT_MESH, Int64(length(ax.meshes)))
    return ax.meshes[end]
end

"""
    meshscatter!(ax, x, y; markersize = 9, color = <cycle>)

2D projection form: circular markers (the sphere-mesh marker of the full 3D
recipe collapses to a disc under the fixed camera — documented divergence).
"""
meshscatter!(ax::Axis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real}; kwargs...) =
    scatter!(ax, x, y; kwargs...)

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
    blo = 0.0
    bhi = 0.0
    if !isempty(p.fillto)
        # WTGAP: conditional tuple-destructure reassignment traps compiled —
        # indexed form (same family as the data_limits splat trap)
        ft = _extrema_finite(p.fillto)
        blo = ft[1]
        bhi = ft[2]
    end
    # bars reach to their baselines (0 / fillto) and extend ±width/2 in x —
    # Makie barplot limits are the bar RECTANGLES' bounding box
    return (xlo - 0.5 * p.width, xhi + 0.5 * p.width,
            min(ylo, blo), max(yhi, bhi))
end
data_limits(p::HeatmapPlot) = (p.xs[1], p.xs[end], p.ys[1], p.ys[end])
data_limits(p::ImagePlot) = (p.x0, p.x1, p.y0, p.y1)
function data_limits(p::HVLines)
    lo, hi = _extrema_finite(p.values)
    # contributes only to its own dimension (the other spans the viewport)
    return p.horizontal ? (Inf, -Inf, lo, hi) : (lo, hi, Inf, -Inf)
end
function data_limits(p::HVSpan)
    lo, _ = _extrema_finite(p.los)
    _, hi = _extrema_finite(p.his)
    return p.horizontal ? (Inf, -Inf, lo, hi) : (lo, hi, Inf, -Inf)
end
data_limits(::ABLines) = (Inf, -Inf, Inf, -Inf)   # never affects autolimits
function data_limits(p::BandPlot)
    xlo, xhi = _extrema_finite(p.x)
    llo, lhi = _extrema_finite(p.ylow)
    hlo, hhi = _extrema_finite(p.yhigh)
    return (xlo, xhi, min(llo, hlo), max(lhi, hhi))
end
function data_limits(p::MeshPlot)
    xlo, xhi = _extrema_finite(p.vx)
    ylo, yhi = _extrema_finite(p.vy)
    return (xlo, xhi, ylo, yhi)
end
function data_limits(p::PolyPlot)
    xlo, xhi = _extrema_finite(p.xs)
    ylo, yhi = _extrema_finite(p.ys)
    return (xlo, xhi, ylo, yhi)
end
function data_limits(p::FilledCurve)
    xlo, xhi = _extrema_finite(p.x)
    ylo, yhi = _extrema_finite(p.y)
    return (xlo, xhi, min(ylo, p.baseline), max(yhi, p.baseline))
end
data_limits(p::SegmentsPlot) = (_extrema_finite(p.x)..., _extrema_finite(p.y)...)

# VENDORED from Makie v0.24.11 — src/makielayout/ticklocators/linear.jl
# (locateticks and helpers — Makie's port of Matplotlib's MaxNLocator).
# License: MIT (see VENDORED.md). This is what `automatic` axis ticks use
# (NOT optimize_ticks, which only serves explicit WilkinsonTicks).

function scale_range(vmin, vmax, n = 1, threshold = 100)
    dv = abs(vmax - vmin)
    meanv = (vmax + vmin) / 2
    offset = if abs(meanv) / dv < threshold
        0.0
    else
        copysign(10^(log10(abs(meanv)) ÷ 1), meanv)
    end
    scale = 10^(log10(dv / n) ÷ 1)
    return scale, offset
end

function _staircase(steps)
    n = length(steps)
    result = Vector{Float64}(undef, 2n)
    for i in 1:(n - 1)
        @inbounds result[i] = 0.1 * steps[i]
    end
    for i in 1:n
        @inbounds result[i + (n - 1)] = steps[i]
    end
    result[end] = 10 * steps[2]
    return result
end

struct EdgeInteger
    step::Float64
    offset::Float64

    function EdgeInteger(step, offset)
        if step <= 0
            error("Step must be positive")
        end
        return new(step, abs(offset))
    end
end

function closeto(e::EdgeInteger, ms, edge)
    tol = if e.offset > 0
        digits = log10(e.offset / e.step)
        tol = max(1.0e-10, 10^(digits - 12))
        min(0.4999, tol)
    else
        1.0e-10
    end
    return abs(ms - edge) < tol
end

function le(e::EdgeInteger, x)
    d, m = divrem(x, e.step)
    return if closeto(e, m / e.step, 1)
        d + 1
    else
        d
    end
end

function ge(e::EdgeInteger, x)
    d, m = divrem(x, e.step)
    return if closeto(e, m / e.step, 0)
        d
    else
        d + 1
    end
end

# WTGAP(284df332c70f, adb7337104b3, 2412608c2d5a, e593fafe2f38) — four WasmTarget runtime traps worked around below,
# behavior pinned by the locateticks oracle tests:
#   (a) range broadcasts `(low:high) .* step .+ x` trap → explicit loops
#   (b) round(x; digits=d) traps → _round_digits
#   (c) log10./abs./diff broadcast chain traps → explicit loop
_round_digits(x::Float64, d::Int) = (s = 10.0^d; round(x * s) / s)

function locateticks(vmin, vmax, n_ideal::Int, _integer::Bool = false, _min_n_ticks::Int = 2)
    @assert isfinite(vmin)
    @assert isfinite(vmax)
    @assert vmin != vmax

    _steps = (1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0)
    _extended_steps = _staircase(_steps)

    scale, offset = scale_range(vmin, vmax, n_ideal)

    _vmin = vmin - offset
    _vmax = vmax - offset

    raw_step = (_vmax - _vmin) / n_ideal

    steps = _extended_steps .* scale

    if _integer
        filter!(steps) do i
            (i < 1) || (abs(i - round(i)) < 0.001)
        end
    end

    istep = findfirst(1:length(steps)) do i
        @inbounds return steps[i] >= raw_step
    end
    ticks = Float64[]
    for istep in istep:-1:1
        step = steps[istep]

        if _integer && (floor(_vmax) - ceil(_vmin) >= _min_n_ticks - 1)
            step = max(1, step)
        end
        best_vmin = (_vmin ÷ step) * step

        edge = EdgeInteger(step, offset)
        low = le(edge, _vmin - best_vmin)
        high = ge(edge, _vmax - best_vmin)
        ticks = Float64[]  # WTGAP(284df332c70f): was (low:high) .* step .+ best_vmin
        # WTGAP(e593fafe2f38): Float64 unit-range iteration traps in wasm; le/ge return
        # whole numbers by contract, so loop over Ints
        for ii in round(Int, low):round(Int, high)
            push!(ticks, ii * step + best_vmin)
        end

        nticks = 0
        for t in ticks
            if _vmin <= t <= _vmax
                nticks += 1
            end
        end

        if nticks >= _min_n_ticks
            break
        end
    end

    for i in eachindex(ticks)
        ticks[i] += offset
    end
    vals = filter(x -> vmin <= x <= vmax, ticks)

    # WTGAP(2412608c2d5a): explicit loop replaces floor(Int, minimum(log10.(abs.(diff(vals)))))
    minlog = Inf
    for i in 1:(length(vals) - 1)
        l = log10(abs(vals[i + 1] - vals[i]))
        l < minlog && (minlog = l)
    end
    exponent = floor(Int, minlog)
    d = max(0, -exponent + 1)
    out = Vector{Float64}(undef, length(vals))
    for i in eachindex(vals)
        out[i] = _round_digits(vals[i], d)  # WTGAP(adb7337104b3)
    end
    return out
end

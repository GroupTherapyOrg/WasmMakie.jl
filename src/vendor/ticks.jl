# VENDORED from PlotUtils v1.4.4 — src/ticks.jl (optimize_ticks and helpers,
# originally from Gadfly.jl by Daniel Jones). License: MIT (see VENDORED.md).
#
# WASM-DIVERGENCE (closed-world adjustments, behavior identical — parity
# asserted against live PlotUtils in CanvasMakie's test suite):
#  - `_logScaleBases::Dict` + scale symbols → `_log_base` if-chain
#  - `@warn "No strict ticks found"` stripped (no logging in compiled paths)
#  - Date/DateTime methods dropped (out of plan scope)
#  - Float64-only entry (the static core's tick path is Float64 throughout)

function bounding_order_of_magnitude(xspan::T, base::T) where {T}
    a = step = 1
    while xspan < base^a
        a -= step
    end

    b = step = 1
    while xspan > base^b
        b += step
    end

    while a + 1 < b
        c = div(a + b, 2)
        if xspan < base^c
            b = c
        else
            a = c
        end
    end

    return b
end

# WTGAP(adb7337104b3 family): kwarg floor/round (digits=/sigdigits=) traps in
# wasm — power-of-ten arithmetic replacements, parity-pinned by the C-002
# subprocess oracle.
# negative powers of ten are inexact doubles — use the divide form there
# (matches Base's rounding identity round(x / 10^k) * 10^k)
function _floor_digits(x::Float64, d::Int)
    if d >= 0
        s = 10.0^d
        return floor(x * s) / s
    else
        h = 10.0^(-d)
        return floor(x / h) * h
    end
end

function _round_sigdigits10(x::Float64, sig::Int)
    x == 0.0 && return 0.0
    isfinite(x) || return x
    e = floor(Int, log10(abs(x)))
    p = sig - 1 - e
    if p >= 0
        s = 10.0^p
        return round(x * s) / s
    else
        h = 10.0^(-p)
        return round(x / h) * h
    end
end

function postdecimal_digits(x::T) where {T}
    for i in floor(Int, log10(floatmin(T))):ceil(Int, log10(floatmax(T)))
        x == _floor_digits(x, i) && return i
    end
    return 0
end

function fallback_ticks(x_min::T, x_max::T, k_min, k_max, strict_span) where {T}
    if !strict_span && x_min ≈ x_max
        x_min, x_max = prevfloat(x_min), nextfloat(x_max)
    end
    return if k_min != 2 && isfinite(x_min) && isfinite(x_max)
        collect(T, range(x_min, x_max; length = k_min)), x_min, x_max
    else
        T[x_min, x_max], x_min, x_max
    end
end

_log_base(scale::Symbol)::Float64 =
    scale === :ln ? Float64(ℯ) : scale === :log2 ? 2.0 : 10.0
_is_log_scale(scale::Symbol)::Bool =
    scale === :ln || scale === :log2 || scale === :log10

Base.@constprop :none function optimize_ticks(
        x_min::Float64,
        x_max::Float64;
        extend_ticks::Bool = false,
        Q::Vector{Tuple{Float64,Float64}} = [(1.0, 1.0), (5.0, 0.9), (2.0, 0.7), (2.5, 0.5), (3.0, 0.2)],
        k_min::Integer = 2,
        k_max::Integer = 10,
        k_ideal::Integer = 5,
        granularity_weight::Float64 = 1 / 4,
        simplicity_weight::Float64 = 1 / 6,
        coverage_weight::Float64 = 1 / 3,
        niceness_weight::Float64 = 1 / 4,
        strict_span::Bool = true,
        span_buffer::Float64 = 0.0,
        scale::Symbol = :identity,
    )
    rtol = 1000.0 * eps(Float64)
    if isapprox(x_min, x_max, rtol = rtol)
        return fallback_ticks(x_min, x_max, k_min, k_max, strict_span)
    end

    Qv = Float64[q[1] for q in Q]
    Qs = Float64[q[2] for q in Q]

    base_float = _log_base(scale)
    base = isinteger(base_float) ? Int(base_float) : 10
    is_log_scale = _is_log_scale(scale)

    for i in 1:2
        sspan = i == 1 ? strict_span : false
        high_score, best, min_best, max_best = optimize_ticks_typed(
            x_min, x_max, extend_ticks, Qv, Qs, k_min, k_max, k_ideal,
            granularity_weight, simplicity_weight, coverage_weight, niceness_weight,
            sspan, span_buffer, is_log_scale, base_float, base,
        )

        if isinf(high_score)
            if !sspan
                return fallback_ticks(x_min, x_max, k_min, k_max, strict_span)
            end
            # WASM-DIVERGENCE: upstream emits @warn "No strict ticks found"
        else
            return best, min_best, max_best
        end
    end
    return Float64[x_min, x_max], x_min, x_max
end

# @constprop :none — constant-propagating into this loop nest sends Julia's
# inference into unbounded recursion (compiler StackOverflow observed when
# called with literal kwargs); upstream avoids it only by luck of call sites.
Base.@constprop :none function optimize_ticks_typed(
        x_min::F, x_max::F, extend_ticks, Qv, Qs, k_min, k_max, k_ideal,
        granularity_weight::F, simplicity_weight::F, coverage_weight::F,
        niceness_weight::F, strict_span, span_buffer, is_log_scale,
        base_float::F, base::Integer,
    ) where {F <: AbstractFloat}
    xspan = x_max - x_min

    z = bounding_order_of_magnitude(xspan, base_float)

    max_post = 0  # WTGAP: generator-maximum → loop
    for q in Qv
        pd = postdecimal_digits(q)
        pd > max_post && (max_post = pd)
    end
    num_digits = (
        bounding_order_of_magnitude(max(abs(x_min), abs(x_max)), base_float) + max_post
    )

    viewmin_best, viewmax_best = x_min, x_max
    high_score = -Inf

    S_best = Vector{F}(undef, k_max)
    len_S_best = length(S_best)

    # WASM-DIVERGENCE (upstream bug, PlotUtils ticks.jl): upstream sizes S
    # at 4k_max, but the k loop reaches 2k_max and the extend_ticks branch
    # writes 3k slots — up to 6k_max. Upstream's @inbounds silently writes
    # out of bounds (results unaffected: reads stay ≤ 2k_max); WasmGC
    # array.set traps on it, and --check-bounds=yes throws. Size correctly.
    S = Vector{F}(undef, (extend_ticks ? 6 : 2) * k_max)

    @inbounds begin
        while 2k_max * base_float^(z + 1) > xspan
            sigdigits = max(1, num_digits - z)
            for k in k_min:(2k_max)
                for qi in 1:length(Qv)  # WTGAP: zip iteration → indexed loop
                    q = Qv[qi]
                    qscore = Qs[qi]
                    tickspan = q * base_float^z
                    tickspan < eps(F) && continue
                    span = (k - 1) * tickspan
                    span < xspan && continue

                    r_float = (x_max - span) / tickspan
                    isfinite(r_float) || continue
                    r = ceil(Int, r_float)

                    (nice_scale = !is_log_scale || isinteger(tickspan)) || (qscore = F(0))

                    while r * tickspan ≤ x_min
                        if extend_ticks
                            for i in 0:(3k - 1)
                                S[i + 1] = (r + i - k) * tickspan
                            end
                            imin = k + 1
                            imax = 2k
                        else
                            for i in 0:(k - 1)
                                S[i + 1] = (r + i) * tickspan
                            end
                            imin = 1
                            imax = k
                        end
                        # WTGAP(adb7337104b3 family): round(sigdigits=, base=)
                        # → power-of-ten form (base is always 10 on this path)
                        S[imin] = viewmin = _round_sigdigits10(S[imin], sigdigits)
                        S[imax] = viewmax = _round_sigdigits10(S[imax], sigdigits)

                        if strict_span
                            viewmin = max(viewmin, x_min)
                            viewmax = min(viewmax, x_max)
                            buf = span_buffer * (viewmax - viewmin)

                            counter = 0
                            for i in 1:imax
                                if (viewmin - buf) ≤ S[i] ≤ (viewmax + buf)
                                    counter += 1
                                    S[counter] = S[i]
                                end
                            end
                            len = counter
                        else
                            len = imax
                        end

                        has_zero = r ≤ 0 && abs(r) < k

                        s = has_zero && nice_scale ? 1 : 0

                        g = 0 < len < 2k_ideal ? 1 - abs(len - k_ideal) / k_ideal : F(0)

                        c = if len > 1
                            effective_span = (len - 1) * tickspan
                            1.5xspan / effective_span
                        else
                            F(0)
                        end

                        score =
                            granularity_weight * g +
                            simplicity_weight * s +
                            coverage_weight * c +
                            niceness_weight * qscore

                        if strict_span && span > xspan
                            score -= 10000
                        end
                        if span ≥ 2xspan
                            score -= 1000
                        end

                        if score > high_score && (k_min ≤ len ≤ k_max)
                            viewmin_best, viewmax_best = viewmin, viewmax
                            high_score, len_S_best = score, len
                            for ci in 1:len  # WTGAP: copyto!+view → loop
                                S_best[ci] = S[ci]
                            end
                        end
                        r += 1
                    end
                end
            end
            z -= 1
        end
    end
    # WTGAP(4c40e07c9230): resize! to a SMALLER length traps in wasm
    # (growing works) — exact-size copy instead
    out_best = Vector{F}(undef, len_S_best)
    for i in 1:len_S_best
        out_best[i] = S_best[i]
    end
    return high_score, out_best, viewmin_best, viewmax_best
end

# Makie's `automatic` linear ticks (T-005): lineaxis.jl:560 dispatches
# automatic → WilkinsonTicks(5, k_min = 3) → PlotUtils.optimize_ticks with
# extend_ticks=false, strict_span=true, default Q/weights. Positional body
# (kwarg call sites trap in wasm, WTGAP dd8864a83097) mirroring the
# optimize_ticks wrapper above.
function wilkinson_ticks_default(x_min::Float64, x_max::Float64)
    rtol = 1000.0 * eps(Float64)
    if isapprox(x_min, x_max, rtol = rtol)
        return fallback_ticks(x_min, x_max, 3, 10, true)[1]
    end
    Qv = Float64[1.0, 5.0, 2.0, 2.5, 3.0]
    Qs = Float64[1.0, 0.9, 0.7, 0.5, 0.2]
    for i in 1:2
        sspan = i == 1 ? true : false
        high_score, best, _, _ = optimize_ticks_typed(
            x_min, x_max, false, Qv, Qs, 3, 10, 5,
            0.25, 1.0 / 6.0, 1.0 / 3.0, 0.25,
            sspan, 0.0, false, 10.0, 10,
        )
        if isinf(high_score)
            if !sspan
                return fallback_ticks(x_min, x_max, 3, 10, true)[1]
            end
        else
            return best
        end
    end
    return Float64[x_min, x_max]
end

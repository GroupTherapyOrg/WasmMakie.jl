# VENDORED from Makie v0.24.11 — src/tick_format.jl (itself a vendoring of the
# Showoff.jl subset Makie used, on Base.Ryu). License: MIT (see VENDORED.md).
#
# WASM-DIVERGENCE: scientific labels return a concrete `TickLabel`
# (base text + superscript text) instead of Makie's RichText spans — the
# static core's text layout renders the superscript itself. Oracle outputs
# from live Makie are hardcoded in the test suite (co-inference hazard, see
# C-002 finding). Ryu writefixed/writeexp need WasmTarget overlays (plan
# W-004) before this compiles to wasm.

const MINUS_SIGN = "−"  # U+2212, as upstream

"""
    TickLabel(text, sup)

One tick label: `text` is the rendered string (`"0.25"`, or the scientific
base `"1.5×10"`), `sup` the superscript exponent text (`""` for plain labels,
`"−9"` for `1.5×10⁻⁹`).
"""
struct TickLabel
    text::String
    sup::String
end

Base.:(==)(a::TickLabel, b::TickLabel) = a.text == b.text && a.sup == b.sup

# Translated verbatim from Makie _plain_label_precision
function _plain_label_precision(xs)
    e10max = -(e10min = typemax(Int))
    for y in xs
        isfinite(y) || continue
        if isapprox(y, 0, atol = 1.0e-16)
            e10 = min(e10min, 0)
        else
            _, e10 = Base.Ryu.reduce_shortest(convert(Float32, y))
        end
        e10min = min(e10min, e10)
        e10max = max(e10max, e10)
    end
    return min(-e10min, -e10max + 16)
end

function _scientific_label_precision(xs)
    ys = [
        x == 0.0 ? 0.0 : round(10.0^(z = log10(abs(Float64(x))); z - floor(z)); sigdigits = 15)
            for x in xs if isfinite(x)
    ]
    return _plain_label_precision(ys)
end

_replace_leading_hyphen(s::AbstractString) = startswith(s, '-') ? MINUS_SIGN * SubString(s, 2) : String(s)

function _format_plain_label(x::AbstractFloat, precision::Integer; minus_sign::Bool = true)
    s = Base.Ryu.writefixed(x, precision)
    return minus_sign ? _replace_leading_hyphen(s) : s
end

"Format `xs` as plain decimal strings with a uniform precision (Makie parity)."
function format_ticks_plain(xs::AbstractArray{<:AbstractFloat}; minus_sign::Bool = true)
    precision = _plain_label_precision(xs)
    return [_format_plain_label(x, precision; minus_sign) for x in xs]
end

function _split_scientific(x::AbstractFloat, precision::Integer)
    s = Base.Ryu.writeexp(x, precision)
    e_idx = something(findfirst('e', s))
    base = SubString(s, 1, prevind(s, e_idx))
    exponent = parse(Int, SubString(s, nextind(s, e_idx)))
    return _replace_leading_hyphen(base), exponent
end

_strip_trailing_zeros(s::AbstractString) = '.' in s ? String(rstrip(rstrip(s, '0'), '.')) : String(s)

function _has_only_zero_fraction(base::AbstractString)
    dot_idx = findfirst('.', base)
    dot_idx === nothing && return true
    return all(==('0'), @view base[nextind(base, dot_idx):end])
end

function _pick_label_style(xs)
    isempty(xs) && return :plain
    x_min, x_max = extrema(xs)
    return (x_max != x_min && abs(log10(x_max - x_min)) > 4) ? :scientific : :plain
end

"""
    format_ticks_auto(xs) -> Vector{TickLabel}

The default linear-axis tick formatter (Makie parity): plain labels for
ordinary ranges, scientific `base×10^exp` labels beyond 4 orders of
magnitude. WASM-DIVERGENCE: returns `TickLabel`s, not RichText.
"""
function format_ticks_auto(xs::AbstractArray{<:AbstractFloat})
    if _pick_label_style(xs) === :plain
        return [TickLabel(s, "") for s in format_ticks_plain(xs)]
    end

    precision = _scientific_label_precision(xs)
    pairs = Union{Nothing,Tuple{String,Int}}[
        iszero(x) ? nothing : (p = _split_scientific(x, precision); (String(p[1]), p[2]))
            for x in xs
    ]

    can_strip = all(p -> p === nothing || _has_only_zero_fraction(p[1]), pairs)

    return map(pairs) do p
        p === nothing && return TickLabel("0", "")
        base, exponent = p
        base_clean = can_strip ? _strip_trailing_zeros(base) : base
        exp_str = exponent < 0 ? MINUS_SIGN * string(-exponent) : string(exponent)
        return TickLabel(base_clean * "×10", exp_str)
    end::Vector{TickLabel}
end

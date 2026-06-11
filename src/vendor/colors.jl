# VENDORED from Makie v0.24.11 — src/colorsampler.jl (interpolated_getindex).
# License: MIT (see VENDORED.md).
#
# WASM-DIVERGENCE: colors are NTuple{4,Float64} (the draw-layer convention)
# and the lerp runs in Float64, where Makie lerps RGBA{Float32} — results
# agree within ~1e-7, irrelevant after 8-bit canvas quantization (asserted
# against live Makie in CanvasMakie's tests).

"Like getindex, but interpolates `i01 ∈ [0,1]` across the colormap."
function interpolated_getindex(cmap::Vector{NTuple{4,Float64}}, i01::Float64)
    isfinite(i01) || error("Looking up a non-finite or NaN value in a colormap is undefined.")
    i1len = (i01 * (length(cmap) - 1)) + 1
    down = floor(Int, i1len)
    up = ceil(Int, i1len)
    down == up && return cmap[down]
    w = i1len - down
    d = cmap[down]
    u = cmap[up]
    return (d[1] * (1.0 - w) + u[1] * w,
            d[2] * (1.0 - w) + u[2] * w,
            d[3] * (1.0 - w) + u[3] * w,
            d[4] * (1.0 - w) + u[4] * w)
end

"Range-normalized variant: clamps `(value - cmin)/(cmax - cmin)` into [0,1]."
function interpolated_getindex(cmap::Vector{NTuple{4,Float64}}, value::Float64,
                               cmin::Float64, cmax::Float64)
    cmin == cmax && error("Can't interpolate in a range where cmin == cmax. This can happen, for example, if a colorrange is set automatically but there's only one unique value present.")
    i01 = clamp((value - cmin) / (cmax - cmin), 0.0, 1.0)
    return interpolated_getindex(cmap, i01)
end

"The default colormap lookup (`:viridis`, Makie's default)."
colormap_color(t::Float64) = interpolated_getindex(VIRIDIS, t)

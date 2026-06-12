# VENDORED (translated) from CairoMakie v0.15.11 — src/image-hmap.jl
# (draw_image fast path + _draw_rect_heatmap). License: MIT (see VENDORED.md).
#
# Pixel data arrives column-major flat: idx = i + (j-1)*ni, where i is the
# x-index (1..ni) and j the y-index (1..nj) — Makie's image[i, j] convention.
# The fast path blits via the buffered-image protocol; orientation is handled
# by the (possibly negative) w/h scale, mirroring Cairo's negative-scale blit.

"""
    draw_image_scaled!(ctx, pixels, ni, nj, x, y, w, h, interpolate)

Fast path: blit an ni×nj image into the screen rect from (x,y) spanning
(w,h) — h is typically negative (y-up data → y-down canvas), which flips the
blit exactly like CairoMakie's negative Cairo scale.
"""
function draw_image_scaled!(ctx, pixels::Vector{NTuple{4,Float64}}, ni::Int64, nj::Int64,
                            x::Float64, y::Float64, w::Float64, h::Float64,
                            interpolate::Bool)
    if interpolate
        # EXTEND_PAD equivalent (the Cairo fast path clips the pattern to the
        # exact rect with pattern_set_extend(PAD)): pad the buffer with a
        # replicated edge-texel ring, blit one texel BEYOND the rect, clip to
        # the rect — bilinear edges sample the padding, never transparency
        # (an unpadded blit fades every edge inward by half a texel)
        img_buf_new(ctx, ni + 2, nj + 2)
        for j in 0:(nj + 1)
            base = (clamp(j, 1, nj) - 1) * ni
            for i in 0:(ni + 1)
                r, g, b, a = pixels[base + clamp(i, 1, ni)]
                img_buf_push_rgba(ctx, round(Int64, 255.0 * r), round(Int64, 255.0 * g),
                                  round(Int64, 255.0 * b), round(Int64, 255.0 * a))
            end
        end
        set_image_smoothing(ctx, Int64(1))
        save(ctx)
        begin_path(ctx)
        rect(ctx, min(x, x + w), min(y, y + h), abs(w), abs(h))
        clip_nonzero(ctx)
        translate(ctx, x, y)
        scale_xy(ctx, w / ni, h / nj)
        draw_image_buf(ctx, -1.0, -1.0, Float64(ni + 2), Float64(nj + 2))
        restore(ctx)
        return nothing
    end
    img_buf_new(ctx, ni, nj)
    for j in 1:nj
        base = (j - 1) * ni
        for i in 1:ni
            r, g, b, a = pixels[base + i]
            img_buf_push_rgba(ctx, round(Int64, 255.0 * r), round(Int64, 255.0 * g),
                              round(Int64, 255.0 * b), round(Int64, 255.0 * a))
        end
    end
    set_image_smoothing(ctx, Int64(0))
    save(ctx)
    translate(ctx, x, y)
    scale_xy(ctx, w / ni, h / nj)
    draw_image_buf(ctx, 0.0, 0.0, Float64(ni), Float64(nj))
    restore(ctx)
    return nothing
end

function _normalize2(p::NTuple{2,Float64})
    n = sqrt(p[1] * p[1] + p[2] * p[2])
    n == 0.0 && return (0.0, 0.0)
    return (p[1] / n, p[2] / n)
end

"""
    draw_rect_heatmap!(ctx, xys, ni, nj, pixels)

Slow path (translated from `_draw_rect_heatmap`): one filled quad per cell.
`xys` is the projected (ni+1)×(nj+1) vertex grid, column-major flat
(idx = i + (j-1)*(ni+1)). Opaque cells are padded toward +i/+j to avoid
antialiasing seams, exactly as upstream.
"""
function draw_rect_heatmap!(ctx, xys::Vector{NTuple{2,Float64}}, ni::Int64, nj::Int64,
                            pixels::Vector{NTuple{4,Float64}})
    stride = ni + 1
    for i in 1:ni
        for j in 1:nj
            p1 = xys[i + (j - 1) * stride]
            p2 = xys[i + 1 + (j - 1) * stride]
            p3 = xys[i + 1 + j * stride]
            p4 = xys[i + j * stride]
            (_isnan2(p1) || _isnan2(p2) || _isnan2(p3) || _isnan2(p4)) && continue

            r, g, b, a = pixels[i + (j - 1) * ni]
            if a == 1.0
                # pad on the +i/+j side (covered by later cells); skip last row/col
                v1 = _normalize2((p2[1] - p1[1], p2[2] - p1[2]))
                v2 = _normalize2((p4[1] - p1[1], p4[2] - p1[2]))
                fi = i != ni ? 1.0 : 0.0
                fj = j != nj ? 1.0 : 0.0
                p2 = (p2[1] + fi * v1[1], p2[2] + fi * v1[2])
                p3 = (p3[1] + fi * v1[1] + fj * v2[1], p3[2] + fi * v1[2] + fj * v2[2])
                p4 = (p4[1] + fj * v2[1], p4[2] + fj * v2[2])
            end

            begin_path(ctx)
            move_to(ctx, p1[1], p1[2])
            line_to(ctx, p2[1], p2[2])
            line_to(ctx, p3[1], p3[2])
            line_to(ctx, p4[1], p4[2])
            close_path(ctx)
            set_fill_rgba(ctx, 255.0 * r, 255.0 * g, 255.0 * b, a)
            fill_nonzero(ctx)
        end
    end
    return nothing
end

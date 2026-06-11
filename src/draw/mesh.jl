# VENDORED (translated) from Makie v0.24.11 — src/jl_rasterizer/main.jl
# (the rasterizer inner loop: edge functions, bounding-box scan, barycentric
# interpolation `w / area`, depth test `<=`, standard_transparency blend).
# License: MIT (see VENDORED.md).
#
# WASM-DIVERGENCE (typed translation, semantics preserved):
#   - shader/uniform machinery (@nospecialize Functions — banned P5) dropped:
#     the only fragment program the 2D core needs is Gouraud vertex color
#   - Colorant framebuffers → flat Vector{NTuple{4,Float64}} RGBA buffer
#   - arbitrary winding accepted (negative-area faces are vertex-swapped;
#     upstream's geometry stage guarantees CCW before the loop)

@inline _edge_function(ax::Float64, ay::Float64, bx::Float64, by::Float64,
                       cx::Float64, cy::Float64) =
    (cx - ax) * (by - ay) - (cy - ay) * (bx - ax)

"""
    rasterize_mesh!(pix, depth, w, h, fx, fy, fz, fr, fg, fb, fa, faces)

Gouraud-rasterize triangles into the RGBA buffer `pix` (row-major flat,
index = x + (y−1)·w) with depth buffer `depth`. Vertex positions are PIXEL
coords (fx/fy), `fz` the per-vertex depth (smaller = nearer, jl_rasterizer's
`<=` test), `faces` flat vertex-index triples (1-based).
"""
function rasterize_mesh!(pix::Vector{NTuple{4,Float64}}, depthbuf::Vector{Float64},
                         w::Int64, h::Int64,
                         fx::Vector{Float64}, fy::Vector{Float64}, fz::Vector{Float64},
                         fr::Vector{Float64}, fg::Vector{Float64},
                         fb::Vector{Float64}, fa::Vector{Float64},
                         faces::Vector{Int64})
    nfaces = div(length(faces), 3)
    for fi in 1:nfaces
        i1 = faces[3 * fi - 2]
        i2 = faces[3 * fi - 1]
        i3 = faces[3 * fi]
        # accept either winding: swap to positive area (upstream guarantees CCW)
        area = _edge_function(fx[i1], fy[i1], fx[i2], fy[i2], fx[i3], fy[i3])
        if area < 0.0
            i2, i3 = i3, i2
            area = -area
        end
        area == 0.0 && continue
        x1 = fx[i1]; y1 = fy[i1]
        x2 = fx[i2]; y2 = fy[i2]
        x3 = fx[i3]; y3 = fy[i3]
        xmin = max(Int64(floor(min(x1, min(x2, x3)))), 1)
        xmax = min(Int64(ceil(max(x1, max(x2, x3)))), w)
        ymin = max(Int64(floor(min(y1, min(y2, y3)))), 1)
        ymax = min(Int64(ceil(max(y1, max(y2, y3)))), h)
        for py in ymin:ymax
            for px in xmin:xmax
                cx = Float64(px)
                cy = Float64(py)
                w1 = _edge_function(x2, y2, x3, y3, cx, cy)
                w2 = _edge_function(x3, y3, x1, y1, cx, cy)
                w3 = _edge_function(x1, y1, x2, y2, cx, cy)
                (w1 >= 0.0 && w2 >= 0.0 && w3 >= 0.0) || continue
                b1 = w1 / area
                b2 = w2 / area
                b3 = w3 / area
                d = b1 * fz[i1] + b2 * fz[i2] + b3 * fz[i3]
                k = px + (py - 1) * w
                d <= depthbuf[k] || continue
                depthbuf[k] = d
                sr = b1 * fr[i1] + b2 * fr[i2] + b3 * fr[i3]
                sg = b1 * fg[i1] + b2 * fg[i2] + b3 * fg[i3]
                sb = b1 * fb[i1] + b2 * fb[i2] + b3 * fb[i3]
                sa = b1 * fa[i1] + b2 * fa[i2] + b3 * fa[i3]
                # standard_transparency: src·α + dest·(1−α)
                dst = pix[k]
                pix[k] = (sa * sr + (1.0 - sa) * dst[1],
                          sa * sg + (1.0 - sa) * dst[2],
                          sa * sb + (1.0 - sa) * dst[3],
                          sa + (1.0 - sa) * dst[4])
            end
        end
    end
    return nothing
end

"""
    draw_mesh!(ctx, fx, fy, fz, fr, fg, fb, fa, faces, x, y, w, h)

Rasterize the mesh (pixel-space vertices relative to the (x, y) origin) at
(w × h) and blit it through the buffered-image protocol.
"""
function draw_mesh!(ctx, fx::Vector{Float64}, fy::Vector{Float64}, fz::Vector{Float64},
                    fr::Vector{Float64}, fg::Vector{Float64}, fb::Vector{Float64},
                    fa::Vector{Float64}, faces::Vector{Int64},
                    x::Float64, y::Float64, w::Int64, h::Int64)
    (w <= 0 || h <= 0) && return nothing
    pix = Vector{NTuple{4,Float64}}(undef, w * h)
    depthbuf = Vector{Float64}(undef, w * h)
    for k in 1:(w * h)
        pix[k] = (0.0, 0.0, 0.0, 0.0)
        depthbuf[k] = Inf
    end
    rasterize_mesh!(pix, depthbuf, w, h, fx, fy, fz, fr, fg, fb, fa, faces)
    # buffered image is column-major flat (i + (j-1)*ni) with ni = w — the
    # rasterizer's row-major x + (y-1)*w is the SAME linear layout
    draw_image_scaled!(ctx, pix, w, h, x, y, Float64(w), Float64(h), false)
    return nothing
end

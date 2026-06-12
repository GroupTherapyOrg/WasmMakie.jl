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
#   - coverage-based edge antialiasing (signed pixel distance per edge,
#     clamped to [0,1], multiplied): upstream jl_rasterizer is hard-edged,
#     but the rendering ORACLE here is Cairo's antialiased mesh patterns —
#     hard edges score outside the reference threshold on band tests
#   - REPLACE compositing within a mesh (highest-coverage fragment wins)
#     instead of standard_transparency blending: the buffer is per-mesh
#     (non-premultiplied RGBA for the ImageData blit) and triangles tile —
#     blending double-darkens translucent fills at shared edges/feathers,
#     where Cairo composites the whole mesh pattern once

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
        # faces touching a NaN vertex draw nothing (Band-with-NaN gaps —
        # matches Cairo, which skips mesh patches with non-finite corners)
        (isfinite(fx[i1]) && isfinite(fy[i1]) && isfinite(fx[i2]) &&
         isfinite(fy[i2]) && isfinite(fx[i3]) && isfinite(fy[i3])) || continue
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
        # per-edge gradient magnitudes (edge-fn change per pixel step) for
        # the signed-distance coverage term
        g1 = sqrt((y3 - y2)^2 + (x3 - x2)^2)
        g2 = sqrt((y1 - y3)^2 + (x1 - x3)^2)
        g3 = sqrt((y2 - y1)^2 + (x2 - x1)^2)
        (g1 == 0.0 || g2 == 0.0 || g3 == 0.0) && continue
        for py in ymin:ymax
            for px in xmin:xmax
                cx = Float64(px)
                cy = Float64(py)
                w1 = _edge_function(x2, y2, x3, y3, cx, cy)
                w2 = _edge_function(x3, y3, x1, y1, cx, cy)
                w3 = _edge_function(x1, y1, x2, y2, cx, cy)
                # coverage: pixels INSIDE stay exactly solid (shared interior
                # edges must not seam — each center is inside one triangle);
                # only the outside of an edge is feathered by signed distance
                c1 = w1 >= 0.0 ? 1.0 : clamp(w1 / g1 + 0.5, 0.0, 1.0)
                c2 = w2 >= 0.0 ? 1.0 : clamp(w2 / g2 + 0.5, 0.0, 1.0)
                c3 = w3 >= 0.0 ? 1.0 : clamp(w3 / g3 + 0.5, 0.0, 1.0)
                cov = c1 * c2 * c3
                cov <= 0.0 && continue
                b1 = max(w1, 0.0) / area
                b2 = max(w2, 0.0) / area
                b3 = max(w3, 0.0) / area
                bs = b1 + b2 + b3
                bs == 0.0 && continue
                b1 /= bs; b2 /= bs; b3 /= bs
                d = b1 * fz[i1] + b2 * fz[i2] + b3 * fz[i3]
                k = px + (py - 1) * w
                d <= depthbuf[k] || continue
                cov >= 0.5 && (depthbuf[k] = d)   # only solid pixels occlude
                sr = b1 * fr[i1] + b2 * fr[i2] + b3 * fr[i3]
                sg = b1 * fg[i1] + b2 * fg[i2] + b3 * fg[i3]
                sb = b1 * fb[i1] + b2 * fb[i2] + b3 * fb[i3]
                sa = cov * (b1 * fa[i1] + b2 * fa[i2] + b3 * fa[i3])
                # within one mesh the triangles tile without overlap — keep
                # the highest-coverage fragment (REPLACE) instead of jl_
                # rasterizer's standard_transparency blend: shared-edge
                # pixels and outside feathers must not double-blend
                # translucent fills (Cairo composites the whole mesh pattern
                # ONCE); the buffer is per-mesh and the canvas blit applies
                # source-over compositing against the scene
                dst = pix[k]
                if sa >= dst[4]
                    pix[k] = (sr, sg, sb, sa)
                end
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

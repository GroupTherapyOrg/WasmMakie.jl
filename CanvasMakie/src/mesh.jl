# Translated from CairoMakie v0.15.11 src/mesh.jl — draw_atomic(Mesh) 2D path
# (camera-type split, screen projection, per-vertex color resolution).
# RENDERING diverges by design: Cairo's CairoPatternMesh Gouraud patches are
# replaced by WasmMakie's vendored jl_rasterizer (R-005) blitted through the
# buffered-image protocol — Canvas2D has no mesh gradients.
#
# Scope (R-006): 2D meshes (Band, density fills, contourf/Poly meshes,
# 2D mesh!). 3D meshes (draw_mesh3D shading) error as unsupported.

function draw_atomic(rctx::WasmMakie.RecordingCtx, scene::Scene, plot::Makie.Mesh)
    attr = plot.attributes
    _has_node(attr, :computed_color) || Makie.compute_colors!(attr)

    if !(Makie.cameracontrols(scene) isa Union{Makie.Camera2D, Makie.PixelCamera, Makie.EmptyCamera})
        error("CanvasMakie: 3D mesh shading not supported (2D scope, R-006)")
    end

    vs = attr[:positions_transformed_f32c][]
    fs = attr[:faces][]
    model = attr[:model_f32c][]
    pv = attr[:projectionview][]
    res = attr[:resolution][]
    color = Makie.compute_colors(attr)   # resolves colormap/scalar/per-vertex (CairoMakie mesh.jl:53)

    nv = length(vs)
    fx = Vector{Float64}(undef, nv)
    fy = Vector{Float64}(undef, nv)
    for i in 1:nv
        p = _project_screen_px(pv, res, model, (vs[i][1], vs[i][2]))
        fx[i] = p[1]
        fy[i] = p[2]
    end

    vr = Vector{Float64}(undef, nv)
    vg = Vector{Float64}(undef, nv)
    vb = Vector{Float64}(undef, nv)
    va = Vector{Float64}(undef, nv)
    if color isa AbstractVector
        length(color) == nv ||
            error("CanvasMakie: per-face/pattern mesh colors not supported (got $(length(color)) colors for $nv vertices)")
        for i in 1:nv
            c = _rgba4(color[i])
            vr[i] = c[1]; vg[i] = c[2]; vb[i] = c[3]; va[i] = c[4]
        end
    else
        c = _rgba4(color)
        for i in 1:nv
            vr[i] = c[1]; vg[i] = c[2]; vb[i] = c[3]; va[i] = c[4]
        end
    end

    faces = Vector{Int64}(undef, 3 * length(fs))
    for (k, f) in enumerate(fs)
        # GLTriangleFace elements are OffsetInteger{-1}; value() is 1-based
        faces[3 * k - 2] = Int64(Makie.GeometryBasics.value(f[1]))
        faces[3 * k - 1] = Int64(Makie.GeometryBasics.value(f[2]))
        faces[3 * k] = Int64(Makie.GeometryBasics.value(f[3]))
    end

    # rasterize over the tight pixel bbox (clamped to the framebuffer)
    xmin = Inf; xmax = -Inf; ymin = Inf; ymax = -Inf
    for i in 1:nv
        (isfinite(fx[i]) && isfinite(fy[i])) || continue   # Band with NaN
        fx[i] < xmin && (xmin = fx[i])
        fx[i] > xmax && (xmax = fx[i])
        fy[i] < ymin && (ymin = fy[i])
        fy[i] > ymax && (ymax = fy[i])
    end
    isfinite(xmin) || return nothing   # all-NaN mesh
    x0 = max(floor(xmin) - 1.0, 0.0)
    y0 = max(floor(ymin) - 1.0, 0.0)
    w = Int64(min(ceil(xmax) + 1.0, Float64(res[1])) - x0)
    h = Int64(min(ceil(ymax) + 1.0, Float64(res[2])) - y0)
    (w <= 0 || h <= 0) && return nothing
    for i in 1:nv
        fx[i] -= x0
        fy[i] -= y0
    end
    WasmMakie.draw_mesh!(rctx, fx, fy, zeros(Float64, nv), vr, vg, vb, va,
                         faces, x0, y0, w, h)
    return nothing
end

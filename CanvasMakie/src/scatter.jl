# Extraction adapter for Scatter — translated from CairoMakie v0.15.11
# src/scatter.jl (MIT): draw_atomic(Scatter), project_marker, project_flipped,
# size_model!, remove_billboard. Marker conversion via Makie.to_spritemarker
# (= CairoMakie's cairo_scatter_marker).
#
# WASM-DIVERGENCE (recorded in the plan):
#  - clip planes / unclipped_indices not applied (consistent with lines, D-002)
#  - Char (glyph) markers need the text engine → loud error until D-006
#  - Matrix (image) markers → loud error until D-004 wiring

# Translated verbatim from CairoMakie size_model!
function size_model!(attr)
    haskey(attr, :size_model) && return
    return Makie.map!(attr, [:f32c_scale, :model, :markerspace, :transform_marker], :size_model) do f32c_scale, model, markerspace, transform_marker
        size_model = transform_marker ? model[Makie.Vec(1, 2, 3), Makie.Vec(1, 2, 3)] : Makie.Mat3d(Makie.LinearAlgebra.I)
        return Makie.Mat3d(f32c_scale[1], 0, 0, 0, f32c_scale[2], 0, 0, 0, f32c_scale[3]) * size_model
    end
end

# Translated verbatim from CairoMakie project_flipped
function project_flipped(trans::Makie.Mat4, res, point::Union{Makie.Point3,Makie.Vec3}, yflip::Bool)
    p4d = Makie.to_ndim(Makie.Vec4d, Makie.to_ndim(Makie.Vec3d, point, 0.0), 1.0)
    clip = trans * p4d
    p = clip[Makie.Vec(1, 2)] ./ clip[4]
    p_yflip = Makie.Vec2d(p[1], (1.0 - 2.0 * yflip) * p[2])
    p_0_to_1 = (p_yflip .+ 1.0) ./ 2.0
    return p_0_to_1 .* res
end

# Translated from CairoMakie project_marker — returns (proj_pos, Mat2f basis)
# (the CairoMatrix twin is dropped; the canvas transform takes the Mat2 parts).
function project_marker(cam, markerspace::Symbol, origin::Makie.Point3, scale::Makie.Vec,
                        rotation, model33::Makie.Mat3, billboard = false)
    xvec = rotation * (model33 * (scale[1] * Makie.Point3d(1, 0, 0)))
    yvec = rotation * (model33 * (scale[2] * Makie.Point3d(0, -1, 0)))
    pv = cam.projectionview
    resolution = cam.resolution
    proj_pos = project_flipped(pv, resolution, origin, true)
    if billboard && Makie.is_data_space(markerspace)
        p4d = cam.view * Makie.to_ndim(Makie.Point4d, origin, 1)
        p4d_clip = p4d[Makie.Vec(1, 2, 3)] / p4d[4]
        xproj = project_flipped(cam.eye_to_clip, resolution, p4d_clip + xvec, true)
        yproj = project_flipped(cam.eye_to_clip, resolution, p4d_clip + yvec, true)
    else
        xproj = project_flipped(pv, resolution, origin + xvec, true)
        yproj = project_flipped(pv, resolution, origin + yvec, true)
    end
    xdiff = xproj - proj_pos
    ydiff = yproj - proj_pos
    return proj_pos, Makie.Mat2f(xdiff..., ydiff...)
end

remove_billboard(x) = x
remove_billboard(b::Makie.Billboard) = b.rotation

_is_degenerate(m::Makie.Mat2f) =
    !all(isfinite, m) || abs(m[1, 1] * m[2, 2] - m[1, 2] * m[2, 1]) < 1.0e-12

function _encode_path(bp::Makie.BezierPath)
    codes = Int64[]
    coords = Float64[]
    for c in bp.commands
        if c isa Makie.MoveTo
            push!(codes, WasmMakie.PATH_MOVE); append!(coords, (c.p[1], c.p[2]))
        elseif c isa Makie.LineTo
            push!(codes, WasmMakie.PATH_LINE); append!(coords, (c.p[1], c.p[2]))
        elseif c isa Makie.CurveTo
            push!(codes, WasmMakie.PATH_CURVE)
            append!(coords, (c.c1[1], c.c1[2], c.c2[1], c.c2[2], c.p[1], c.p[2]))
        elseif c isa Makie.ClosePath
            push!(codes, WasmMakie.PATH_CLOSE)
        elseif c isa Makie.EllipticalArc
            push!(codes, WasmMakie.PATH_ARC)
            append!(coords, (c.c[1], c.c[2], c.r1, c.r2, c.angle, c.a1, c.a2))
        end
    end
    return codes, coords
end

_rgba4(c) = (Float64(ColorTypes.red(c)), Float64(ColorTypes.green(c)),
             Float64(ColorTypes.blue(c)), Float64(ColorTypes.alpha(c)))

function draw_atomic(rctx::WasmMakie.RecordingCtx, scene::Scene, plot::Makie.Scatter)
    attr = plot.attributes
    isempty(attr[:positions][]) && return
    Makie.add_computation!(attr, scene, Val(:meshscatter_f32c_scale))
    _has_node(attr, :computed_color) || Makie.compute_colors!(attr)
    _has_node(attr, :positions_in_markerspace) || Makie.register_positions_projected!(
        scene.compute, attr, Makie.Point3d;
        input_name = :positions_transformed_f32c, output_name = :positions_in_markerspace,
        input_space = :space, output_space = :markerspace, apply_clip_planes = false
    )
    _has_node(attr, :canvas_marker) || Makie.map!(Makie.to_spritemarker, attr, :marker, :canvas_marker)
    size_model!(attr)
    if !haskey(attr, :eye_to_clip)
        Makie.add_input!(attr, :eye_to_clip, scene.compute.projection)
        Makie.add_input!(attr, :cam_view, scene.compute.view)
    end

    positions = attr[:positions_in_markerspace][]
    colors = attr[:computed_color][]
    markersize = attr[:markersize][]
    strokecolor = attr[:strokecolor][]
    strokewidth = attr[:strokewidth][]
    marker = attr[:canvas_marker][]
    marker_offset = attr[:marker_offset][]
    rotations = attr[:converted_rotation][]
    billboard = attr[:billboard][]
    markerspace = attr[:markerspace][]
    sm = attr[:size_model][]
    cam = (resolution = attr[:resolution][], projectionview = attr[:projectionview][],
           eye_to_clip = attr[:eye_to_clip][], view = attr[:cam_view][])

    for i in eachindex(positions)
        position = positions[i]
        any(isnan, position) && continue
        col = Makie.sv_getindex(colors, i)
        ms = Makie.sv_getindex(markersize, i)
        scol = Makie.sv_getindex(strokecolor, i)
        swidth = Float64(Makie.sv_getindex(strokewidth, i))
        m = Makie.sv_getindex(marker, i)
        moff = Makie.sv_getindex(marker_offset, i)
        rot = remove_billboard(Makie.sv_getindex(rotations, i))
        scale = Makie.to_ndim(Makie.Vec2d, ms, 0.0)
        (any(isnan, scale) || all(x -> abs(x) < 1.0e-12, scale)) && continue

        origin = position .+ sm * Makie.to_ndim(Makie.Vec3d, moff, 0)
        proj_pos, jl_mat = project_marker(cam, markerspace, Makie.Point3d(origin), scale, rot, sm, billboard)
        _is_degenerate(jl_mat) && continue

        x, y = Float64(proj_pos[1]), Float64(proj_pos[2])
        m11, m21, m12, m22 = Float64(jl_mat[1, 1]), Float64(jl_mat[2, 1]), Float64(jl_mat[1, 2]), Float64(jl_mat[2, 2])
        fr, fg, fb, fa = _rgba4(col)
        sr, sg, sb, sa = _rgba4(Makie.to_color(scol))

        if m isa Type && m <: Makie.Circle
            WasmMakie.draw_marker_circle!(rctx, x, y, m11, m21, m12, m22,
                fr, fg, fb, fa, sr, sg, sb, sa, swidth)
        elseif m isa Makie.FastPixel || (m isa Type && m <: Makie.Rect)
            WasmMakie.draw_marker_rect!(rctx, x, y, m11, m21, m12, m22,
                fr, fg, fb, fa, sr, sg, sb, sa, swidth)
        elseif m isa Makie.BezierPath
            codes, coords = _encode_path(m)
            WasmMakie.draw_marker_path!(rctx, x, y, m11, m21, m12, m22, codes, coords,
                fr, fg, fb, fa, sr, sg, sb, sa, swidth)
        elseif m isa Char
            error("CanvasMakie: Char markers need glyph rendering (plan D-006)")
        else
            error("CanvasMakie: marker $(typeof(m)) not implemented yet")
        end
    end
    return
end

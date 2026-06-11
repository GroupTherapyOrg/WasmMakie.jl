# Text rendering — host mode.
#
# The per-glyph extraction loop is translated from CairoMakie v0.15.11
# src/scatter.jl draw_text (MIT). The RENDERING diverges by design: CairoMakie
# rasterizes glyphs through Cairo's FreeType integration (cairo_show_glyphs);
# we decompose each glyph's FreeType outline into the encoded-path protocol
# and fill it through the shared draw layer — the same geometry Cairo uses,
# drawn as paths, which keeps the wasm/browser story font-engine-free.
#
# WASM-DIVERGENCE (recorded in the plan):
#  - glyph batching dropped (each glyph draws its own path; correctness first)
#  - glow is a loud error when actually requested (glowwidth > 0 + visible)
#  - clip planes / unclipped_indices not applied (consistent with D-002…D-005)

import Makie.FreeTypeAbstraction as FTA
import Makie.FreeTypeAbstraction.FreeType as FT

# ── FreeType outline → encoded path (EM-normalized, y-up) ────────────────
# Standard TrueType/CFF outline walk: tag bit 0 = on-curve, bit 1 = cubic
# control. Conic runs synthesize implied on-curve midpoints.
function _emit_contour!(codes::Vector{Int64}, coords::Vector{Float64},
                        pts::Vector{NTuple{2,Float64}}, tags::Vector{UInt8})
    n = length(pts)
    n == 0 && return
    on(i) = (tags[i] & 0x01) != 0
    iscubic(i) = (tags[i] & 0x02) != 0

    if !on(1)
        if on(n)  # rotate so the contour starts on-curve
            pts = vcat(pts[n:n], pts[1:(n - 1)])
            tags = vcat(tags[n:n], tags[1:(n - 1)])
        else      # both endpoints off-curve: synthesize the midpoint start
            mid = ((pts[1][1] + pts[n][1]) / 2, (pts[1][2] + pts[n][2]) / 2)
            pts = vcat([mid], pts)
            tags = vcat(UInt8[0x01], tags)
        end
        n = length(pts)
    end
    start = pts[1]
    push!(codes, WasmMakie.PATH_MOVE); append!(coords, start)

    i = 2
    while i <= n
        if on(i)
            push!(codes, WasmMakie.PATH_LINE); append!(coords, pts[i])
            i += 1
        elseif iscubic(i)
            c1 = pts[i]
            c2 = i + 1 <= n ? pts[i + 1] : start
            ep = i + 2 <= n ? pts[i + 2] : start
            push!(codes, WasmMakie.PATH_CURVE); append!(coords, (c1..., c2..., ep...))
            i += 3
        else  # conic
            ctrl = pts[i]
            if i + 1 <= n
                if on(i + 1)
                    push!(codes, WasmMakie.PATH_QUAD); append!(coords, (ctrl..., pts[i + 1]...))
                    i += 2
                else  # two offs: implied on-curve midpoint, keep next as ctrl
                    mid = ((ctrl[1] + pts[i + 1][1]) / 2, (ctrl[2] + pts[i + 1][2]) / 2)
                    push!(codes, WasmMakie.PATH_QUAD); append!(coords, (ctrl..., mid...))
                    i += 1
                end
            else  # wraps to the start point
                push!(codes, WasmMakie.PATH_QUAD); append!(coords, (ctrl..., start...))
                i += 1
            end
        end
    end
    push!(codes, WasmMakie.PATH_CLOSE)
    return
end

const _GLYPH_PATH_CACHE = Dict{Tuple{UInt,UInt32},Tuple{Vector{Int64},Vector{Float64}}}()

"""
    glyph_encoded_path(font, glyphindex) -> (codes, coords)

Decompose a glyph's FreeType outline into the encoded-path protocol,
normalized to the EM square (y-up — `draw_marker_path!` flips). Cached.
"""
function glyph_encoded_path(font::FTA.FTFont, glyphindex::Integer)
    key = (UInt(reinterpret(UInt, getfield(font, :ft_ptr))), UInt32(glyphindex))
    return get!(_GLYPH_PATH_CACHE, key) do
        codes = Int64[]
        coords = Float64[]
        Base.@lock font.lock begin
            err = FT.FT_Load_Glyph(font, FT.FT_UInt(glyphindex), FT.FT_LOAD_NO_SCALE)
            err == 0 || error("CanvasMakie: FT_Load_Glyph failed (err $err, glyph $glyphindex)")
            face = unsafe_load(getfield(font, :ft_ptr))
            upem = Float64(face.units_per_EM)
            outline = unsafe_load(face.glyph).outline
            startp = 1
            for c in 1:outline.n_contours
                endp = Int(unsafe_load(outline.contours, c)) + 1  # 0-based ends
                npts = endp - startp + 1
                if npts > 0
                    pts = Vector{NTuple{2,Float64}}(undef, npts)
                    tags = Vector{UInt8}(undef, npts)
                    for k in 1:npts
                        v = unsafe_load(outline.points, startp + k - 1)
                        pts[k] = (Float64(v.x) / upem, Float64(v.y) / upem)
                        tags[k] = reinterpret(UInt8, unsafe_load(outline.tags, startp + k - 1))
                    end
                    _emit_contour!(codes, coords, pts, tags)
                end
                startp = endp + 1
            end
        end
        (codes, coords)
    end
end

# ── draw_atomic(Text): extraction loop translated from CairoMakie draw_text ─
function draw_atomic(rctx::WasmMakie.RecordingCtx, scene::Scene, plot::Makie.Text)
    attr = plot.attributes
    _has_node(attr, :positions_in_markerspace) || Makie.register_positions_projected!(
        scene.compute, attr, Makie.Point3d;
        input_name = :positions_transformed_f32c, output_name = :positions_in_markerspace,
        input_space = :space, output_space = :markerspace, apply_clip_planes = false
    )
    Makie.add_computation!(attr, scene, Val(:meshscatter_f32c_scale))
    size_model!(attr)
    if !haskey(attr, :eye_to_clip)
        Makie.add_input!(attr, :eye_to_clip, scene.compute.projection)
        Makie.add_input!(attr, :cam_view, scene.compute.view)
    end

    positions = attr[:positions_in_markerspace][]
    text_blocks = attr[:text_blocks][]
    font_per_char = attr[:font_per_char][]
    glyphindices = attr[:glyphindices][]
    marker_offset = attr[:marker_offset][]
    text_rotation = attr[:text_rotation][]
    text_scales = attr[:text_scales][]
    text_strokewidth = attr[:text_strokewidth][]
    text_strokecolor = attr[:text_strokecolor][]
    text_color = attr[:text_color][]
    markerspace = attr[:markerspace][]
    glowwidth = attr[:glowwidth][]
    glowcolor = attr[:glowcolor][]
    sm = attr[:size_model][]
    cam = (resolution = attr[:resolution][], projectionview = attr[:projectionview][],
           eye_to_clip = attr[:eye_to_clip][], view = attr[:cam_view][])

    if Makie.to_value(glowwidth) > 0 && Float64(ColorTypes.alpha(Makie.to_color(Makie.to_value(glowcolor)))) > 0
        error("CanvasMakie: text glow not implemented yet")
    end

    for (block_idx, glyph_indices) in enumerate(text_blocks)
        glyph_pos = positions[block_idx]
        for glyph_idx in glyph_indices
            glyph = glyphindices[glyph_idx]
            glyph == 0 && continue  # whitespace / no glyph

            offset = marker_offset[glyph_idx]
            font = font_per_char[glyph_idx]
            rotation = Makie.sv_getindex(text_rotation, glyph_idx)
            color = Makie.sv_getindex(text_color, glyph_idx)
            strokewidth = Float64(Makie.sv_getindex(text_strokewidth, glyph_idx))
            strokecolor = Makie.sv_getindex(text_strokecolor, glyph_idx)
            scale = Makie.sv_getindex(text_scales, glyph_idx)

            gp3 = glyph_pos .+ sm * offset
            any(isnan, gp3) && continue

            glyphpos, jl_mat = project_marker(cam, markerspace, Makie.Point3d(gp3),
                                              Makie.to_ndim(Makie.Vec2d, scale, 0.0), rotation, sm)
            _is_degenerate(jl_mat) && continue

            codes, coords = glyph_encoded_path(font, glyph)
            isempty(codes) && continue

            fr, fg, fb, fa = _rgba4(Makie.to_color(color))
            sr, sg, sb, sa = _rgba4(Makie.to_color(strokecolor))
            WasmMakie.draw_marker_path!(rctx,
                Float64(glyphpos[1]), Float64(glyphpos[2]),
                Float64(jl_mat[1, 1]), Float64(jl_mat[2, 1]), Float64(jl_mat[1, 2]), Float64(jl_mat[2, 2]),
                codes, coords, fr, fg, fb, fa, sr, sg, sb, sa, strokewidth)
        end
    end
    return
end
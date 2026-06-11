# Extraction adapter for Lines/LineSegments — translated from CairoMakie
# v0.15.11 src/lines.jl (MIT). The FULL clipping pipeline is vendored verbatim
# (D-008 round 4): clip planes + near/far w-clipping with per-point color and
# linewidth interpolation at plane crossings (add_projected_line_points!,
# clip_line_points, clip_lines!, clip_linesegments!, clip2screen).

import LinearAlgebra: dot

# Translated verbatim from CairoMakie utils.jl clip2screen
function clip2screen(p, res)
    s = Makie.Vec2f(0.5f0, -0.5f0) .* p[Makie.Vec(1, 2)] / p[4] .+ 0.5f0
    return res .* s
end

# Translated verbatim from CairoMakie add_projected_line_points!
function add_projected_line_points!(attr)
    _has_node(attr, :clipped_points) && return
    inputs = [:positions_transformed_f32c, :model_f32c, :projectionview]
    Makie.map!(attr, inputs, :clipspace_points) do points, model_f32c, projectionview
        transform = projectionview * model_f32c
        return map(points) do point
            return transform * Makie.to_ndim(Makie.Vec4d, Makie.to_ndim(Makie.Vec3d, point, 0), 1)
        end
    end
    Makie.add_computation!(attr, Val(:uniform_clip_planes), :clip)
    inputs = [:clipspace_points, :computed_color, :linewidth, :is_lines_plot, :uniform_clip_planes, :resolution]
    outputs = [:clipped_points, :clipped_colors, :clipped_linewidths]
    return Makie.register_computation!(attr, inputs, outputs) do (clip_points, colors, linewidths, is_lines_plot, clip_planes, res), _, _
        return clip_line_points(clip_points, colors, linewidths, is_lines_plot, clip_planes, res)
    end
end

# Translated verbatim from CairoMakie clip_line_points
function clip_line_points(clip_points, colors, linewidths, is_lines_plot, clip_planesv4f, res)
    per_point_colors = colors isa AbstractArray
    per_point_linewidths = is_lines_plot && (linewidths isa AbstractArray)

    clip_planes = map(clip_planesv4f) do plane
        return Makie.Plane3f(plane[Makie.Vec(1, 2, 3)], plane[4])
    end

    # Fix lines with points far outside the clipped region not drawing at all
    push!(
        clip_planes,
        Makie.Plane3f(Makie.Vec3f(-1, 0, 0), -1.0f0), Makie.Plane3f(Makie.Vec3f(+1, 0, 0), -1.0f0),
        Makie.Plane3f(Makie.Vec3f(0, -1, 0), -1.0f0), Makie.Plane3f(Makie.Vec3f(0, +1, 0), -1.0f0)
    )

    screen_points = sizehint!(Makie.Vec2f[], length(clip_points))
    color_output = sizehint!(eltype(colors)[], length(clip_points))
    linewidth_output = sizehint!(eltype(linewidths)[], length(clip_points))

    if is_lines_plot
        clip_lines!(
            clip_points, colors, linewidths, clip_planes, res, per_point_colors, per_point_linewidths,
            screen_points, color_output, linewidth_output
        )
    else
        clip_linesegments!(
            clip_points, colors, clip_planes, res, per_point_colors,
            screen_points, color_output
        )
    end
    return screen_points, ifelse(per_point_colors, color_output, colors),
        ifelse(per_point_linewidths, linewidth_output, linewidths)
end

# Translated verbatim from CairoMakie clip_linesegments!
function clip_linesegments!(
        clip_points, colors, clip_planes, res, per_point_colors,
        screen_points, color_output
    )
    local c1, c2
    for i in 1:2:(length(clip_points) - 1)
        if per_point_colors
            c1 = colors[i]
            c2 = colors[i + 1]
        end

        p1 = clip_points[i]
        p2 = clip_points[i + 1]
        v = p2 - p1

        if p1[4] <= 0.0
            p1 = p1 + (-p1[4] - p1[3]) / (v[3] + v[4]) * v
            if per_point_colors
                c1 = c1 + (-p1[4] - p1[3]) / (v[3] + v[4]) * (c2 - c1)
            end
        end
        if p2[4] <= 0.0
            p2 = p2 + (-p2[4] - p2[3]) / (v[3] + v[4]) * v
            if per_point_colors
                c2 = c2 + (-p2[4] - p2[3]) / (v[3] + v[4]) * (c2 - c1)
            end
        end

        for plane in clip_planes
            d1 = dot(plane.normal, Makie.Vec3f(p1)) - plane.distance * p1[4]
            d2 = dot(plane.normal, Makie.Vec3f(p2)) - plane.distance * p2[4]

            if (d1 < 0.0) && (d2 < 0.0)
                p1 = Makie.Vec4f(NaN)
                p2 = Makie.Vec4f(NaN)
                break
            elseif (d1 < 0.0)
                p1 = p1 - d1 * (p2 - p1) / (d2 - d1)
                if per_point_colors
                    c1 = c1 - d1 * (c2 - c1) / (d2 - d1)
                end
            elseif (d2 < 0.0)
                p2 = p2 - d2 * (p1 - p2) / (d1 - d2)
                if per_point_colors
                    c2 = c2 - d2 * (c1 - c2) / (d1 - d2)
                end
            end
        end

        push!(screen_points, clip2screen(p1, res), clip2screen(p2, res))
        if per_point_colors
            push!(color_output, c1, c2)
        end
    end
    return
end

# Translated verbatim from CairoMakie clip_lines!
function clip_lines!(
        clip_points, colors, linewidths, clip_planes, res, per_point_colors, per_point_linewidths,
        screen_points, color_output, linewidth_output
    )
    local c1, c2
    last_is_nan = true
    for i in 1:(length(clip_points) - 1)
        hidden = false
        disconnect1 = false
        disconnect2 = false

        if per_point_colors
            c1 = colors[i]
            c2 = colors[i + 1]
        end

        p1 = clip_points[i]
        p2 = clip_points[i + 1]
        v = p2 - p1

        if p1[4] <= 0.0
            disconnect1 = true
            p1 = p1 + (-p1[4] - p1[3]) / (v[3] + v[4]) * v
            if per_point_colors
                c1 = c1 + (-p1[4] - p1[3]) / (v[3] + v[4]) * (c2 - c1)
            end
        end
        if p2[4] <= 0.0
            disconnect2 = true
            p2 = p2 + (-p2[4] - p2[3]) / (v[3] + v[4]) * v
            if per_point_colors
                c2 = c2 + (-p2[4] - p2[3]) / (v[3] + v[4]) * (c2 - c1)
            end
        end

        for plane in clip_planes
            d1 = dot(plane.normal, Makie.Vec3f(p1)) - plane.distance * p1[4]
            d2 = dot(plane.normal, Makie.Vec3f(p2)) - plane.distance * p2[4]

            if (d1 < 0.0) && (d2 < 0.0)
                hidden = true
                break
            elseif (d1 < 0.0)
                disconnect1 = true
                p1 = p1 - d1 * (p2 - p1) / (d2 - d1)
                if per_point_colors
                    c1 = c1 - d1 * (c2 - c1) / (d2 - d1)
                end
            elseif (d2 < 0.0)
                disconnect2 = true
                p2 = p2 - d2 * (p1 - p2) / (d1 - d2)
                if per_point_colors
                    c2 = c2 - d2 * (c1 - c2) / (d1 - d2)
                end
            end
        end

        if hidden && !last_is_nan
            last_is_nan = true
            push!(screen_points, Makie.Vec2f(NaN))
            if per_point_linewidths
                push!(linewidth_output, linewidths[i])
            end
            if per_point_colors
                push!(color_output, c1)
            end
        elseif !hidden
            if disconnect1 && !last_is_nan
                push!(screen_points, Makie.Vec2f(NaN))
                if per_point_linewidths
                    push!(linewidth_output, linewidths[i])
                end
                if per_point_colors
                    push!(color_output, c1)
                end
            end

            last_is_nan = false
            push!(screen_points, clip2screen(p1, res))
            if per_point_linewidths
                push!(linewidth_output, linewidths[i])
            end
            if per_point_colors
                push!(color_output, c1)
            end

            if disconnect2
                last_is_nan = true
                push!(screen_points, clip2screen(p2, res), Makie.Vec2f(NaN))
                if per_point_linewidths
                    push!(linewidth_output, linewidths[i + 1], linewidths[i + 1])
                end
                if per_point_colors
                    push!(color_output, c2, c2) # relevant, irrelevant
                end
            end
        end
    end

    return if !last_is_nan
        push!(screen_points, clip2screen(clip_points[end], res))
        if per_point_linewidths
            push!(linewidth_output, linewidths[end])
        end
        if per_point_colors
            push!(color_output, colors[end])
        end
    end
end

_cap_int(x::Symbol, key) = Int64(Makie.convert_attribute(x, key))
_cap_int(x, key) = Int64(x)

function draw_atomic(rctx::WasmMakie.RecordingCtx, scene::Scene,
                     plot::PT) where {PT <: Union{Makie.Lines, Makie.LineSegments}}
    attr = plot.attributes
    is_lines = plot isa Makie.Lines
    _has_node(attr, :is_lines_plot) || Makie.add_constant!(attr, :is_lines_plot, is_lines)
    if plot isa Makie.LineSegments
        _has_node(attr, :joinstyle) || Makie.add_constant!(attr, :joinstyle, nothing)
        _has_node(attr, :miter_limit) || Makie.add_constant!(attr, :miter_limit, nothing)
    end
    _has_node(attr, :computed_color) || Makie.compute_colors!(attr)
    add_projected_line_points!(attr)

    screen_pts = attr[:clipped_points][]
    isempty(screen_pts) && return
    positions = NTuple{2,Float64}[(Float64(p[1]), Float64(p[2])) for p in screen_pts]

    color = attr[:clipped_colors][]
    linewidth = attr[:clipped_linewidths][]
    # Cairo draws nothing at linewidth 0; Canvas IGNORES lineWidth = 0 and
    # keeps the stale width (R-006: Band's invisible outline child)
    maxlw = linewidth isa AbstractArray ? (isempty(linewidth) ? 0.0 : maximum(linewidth)) :
            Float64(linewidth)
    maxlw <= 0.0 && return
    linestyle = attr[:linestyle][]
    linecap = _cap_int(attr[:linecap][], Makie.Key{:linecap}())
    joinstyle_raw = is_lines ? attr[:joinstyle][] : 0
    joinstyle = isnothing(joinstyle_raw) ? Int64(0) : _cap_int(joinstyle_raw, Makie.Key{:joinstyle}())
    miter_raw = is_lines ? attr[:miter_limit][] : nothing
    miter_angle = isnothing(miter_raw) ? 2pi / 3 : Float64(miter_raw)
    miter_limit = 2.0 * Makie.miter_angle_to_distance(miter_angle)

    if color isa AbstractArray || linewidth isa AbstractArray
        # per-vertex path (CairoMakie draw_multi): dash stays UNSCALED here —
        # re-scaled by each stroke's width upstream
        n = length(positions)
        colors4 = NTuple{4,Float64}[_rgba4(Makie.to_color(Makie.sv_getindex(color, i))) for i in 1:n]
        widths = Float64[Float64(Makie.sv_getindex(linewidth, i)) for i in 1:n]
        dash = isnothing(linestyle) ? WasmMakie.NO_DASH : diff(Float64.(linestyle))
        WasmMakie.draw_lines_multi!(rctx, positions, is_lines, colors4, widths,
                                    dash, linecap, joinstyle, miter_limit)
        return
    end

    pattern = isnothing(linestyle) ? WasmMakie.NO_DASH :
        WasmMakie.linestyle_to_pattern(Float64.(linestyle), Float64(linewidth))
    WasmMakie.draw_lines!(rctx, positions, is_lines,
        Float64(ColorTypes.red(color)), Float64(ColorTypes.green(color)),
        Float64(ColorTypes.blue(color)), Float64(ColorTypes.alpha(color)),
        Float64(linewidth), pattern, linecap, joinstyle, miter_limit)
    return
end

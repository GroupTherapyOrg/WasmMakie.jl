# Extraction adapter for Lines/LineSegments — translated from CairoMakie
# v0.15.11 src/lines.jl (MIT): pulls projected positions + style out of the
# plot's compute graph and hands plain data to WasmMakie's draw layer.
#
# WASM-DIVERGENCE (scoped to D-002, recorded in the plan):
#  - clip planes are not applied (CairoMakie's clip_line_points); positions
#    project clipspace→screen directly. Reference burn-down (D-008) decides
#    whether the full clipper gets vendored.
#  - per-vertex colors/linewidths (CairoMakie draw_multi) are rejected loudly.

_has_node(attr, name::Symbol) = haskey(attr.outputs, name) || haskey(attr.inputs, name)

# Translated from CairoMakie add_projected_line_points! (clipspace stage only)
function _add_clipspace_points!(attr)
    _has_node(attr, :clipspace_points) && return
    inputs = [:positions_transformed_f32c, :model_f32c, :projectionview]
    Makie.map!(attr, inputs, :clipspace_points) do points, model_f32c, projectionview
        transform = projectionview * model_f32c
        return map(points) do point
            return transform * Makie.to_ndim(Makie.Vec4d, Makie.to_ndim(Makie.Vec3d, point, 0), 1)
        end
    end
    return
end

_cap_int(x::Symbol, key) = Int64(Makie.convert_attribute(x, key))
_cap_int(x, key) = Int64(x)

function draw_atomic(rctx::WasmMakie.RecordingCtx, scene::Scene,
                     plot::PT) where {PT <: Union{Makie.Lines, Makie.LineSegments}}
    attr = plot.attributes
    is_lines = plot isa Makie.Lines
    _has_node(attr, :computed_color) || Makie.compute_colors!(attr)
    _add_clipspace_points!(attr)

    clipspace = attr[:clipspace_points][]
    isempty(clipspace) && return
    res = attr[:resolution][]
    # clipspace → device pixels, y-down (matches Cairo surface coords)
    positions = map(clipspace) do p
        w = Float64(p[4])
        return ((Float64(p[1]) / w + 1.0) * 0.5 * Float64(res[1]),
                (1.0 - Float64(p[2]) / w) * 0.5 * Float64(res[2]))
    end::Vector{NTuple{2,Float64}}

    color = attr[:computed_color][]
    linewidth = attr[:linewidth][]
    linestyle = attr[:linestyle][]
    linecap = _cap_int(attr[:linecap][], Makie.Key{:linecap}())
    joinstyle = is_lines ? _cap_int(attr[:joinstyle][], Makie.Key{:joinstyle}()) : Int64(0)
    miter_angle = is_lines ? Float64(attr[:miter_limit][]) : 2pi / 3
    miter_limit = 2.0 * Makie.miter_angle_to_distance(miter_angle)

    if color isa AbstractArray || linewidth isa AbstractArray
        # per-vertex path (CairoMakie draw_multi): broadcast to per-point data;
        # dash stays UNSCALED here — re-scaled by each stroke's width upstream
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

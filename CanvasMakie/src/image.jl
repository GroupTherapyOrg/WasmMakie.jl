# Extraction adapter for Heatmap/Image — translated from CairoMakie v0.15.11
# src/image-hmap.jl (MIT): image_grid!, regularly_spaced_array_to_range,
# draw_atomic(Heatmap/Image), fast-path conditions.
#
# WASM-DIVERGENCE (recorded in the plan):
#  - clip planes not applied (consistent with D-002/D-003)
#  - non-default `uv_transform` on Image is not consumed; orientation is
#    pinned by oracle-derived tests (default y-flip semantics)

# Translated verbatim from CairoMakie regularly_spaced_array_to_range
function regularly_spaced_array_to_range(arr)
    diffs = unique!(sort!(diff(arr)))
    step = sum(diffs) ./ length(diffs)
    if all(x -> x ≈ step, diffs)
        m, M = extrema(arr)
        if step < zero(step)
            m, M = M, m
        end
        return range(m; step = step, length = length(arr))
    else
        return arr
    end
end
regularly_spaced_array_to_range(arr::AbstractRange) = arr

# Translated from CairoMakie image_grid!
function image_grid!(::typeof(Makie.heatmap), attr)
    _has_node(attr, :grid_x) && return
    Makie.add_computation!(attr, nothing, Val(:heatmap_transform))
    return Makie.register_computation!(attr, [:x_transformed_f32c, :y_transformed_f32c], [:grid_x, :grid_y]) do (x, y), _, _
        return (regularly_spaced_array_to_range(x), regularly_spaced_array_to_range(y))
    end
end

function image_grid!(::typeof(Makie.image), attr)
    _has_node(attr, :grid_x) && return
    return Makie.register_computation!(attr, [:positions_transformed_f32c, :image], [:grid_x, :grid_y]) do (positions, image), _, _
        (x0, y0), _, (x1, y1), _ = positions
        xs = range(x0, x1, length = size(image, 1) + 1)
        ys = range(y0, y1, length = size(image, 2) + 1)
        return (xs, ys)
    end
end

# Translated from CairoMakie cairo_project_to_screen_impl (point form):
# model + projectionview → ndc → y-flipped device pixels.
function _project_screen_px(pv::Makie.Mat4, res, model::Makie.Mat4, p)
    transform = pv * model
    p4 = transform * Makie.to_ndim(Makie.Vec4d, Makie.to_ndim(Makie.Vec3d, Makie.Point2d(p[1], p[2]), 0.0), 1.0)
    w = Float64(p4[4])
    return ((Float64(p4[1]) / w + 1.0) * 0.5 * Float64(res[1]),
            (1.0 - Float64(p4[2]) / w) * 0.5 * Float64(res[2]))
end

function _flat_pixels(colors::AbstractMatrix)
    ni, nj = size(colors)
    pixels = Vector{NTuple{4,Float64}}(undef, ni * nj)
    for j in 1:nj, i in 1:ni
        pixels[i + (j - 1) * ni] = _rgba4(colors[i, j])
    end
    return pixels
end

function draw_atomic(rctx::WasmMakie.RecordingCtx, scene::Scene,
                     plot::PT) where {PT <: Union{Makie.Heatmap, Makie.Image}}
    attr = plot.attributes
    image_grid!(Makie.plotfunc(plot), attr)
    _has_node(attr, :computed_color) || Makie.compute_colors!(attr)

    xs = attr[:grid_x][]
    ys = attr[:grid_y][]
    model = attr[:model_f32c][]
    pv = attr[:projectionview][]
    res = attr[:resolution][]
    interpolate = attr[:interpolate][]
    colors = attr[:computed_color][]

    is_regular_grid = xs isa AbstractRange && ys isa AbstractRange
    is_identity_transform = Makie.is_translation_scale_matrix(model)
    is_xy_aligned = Makie.is_translation_scale_matrix(pv)

    if interpolate
        if !is_regular_grid
            error("$(typeof(xs)) with interpolate = true with a non-regular grid is not supported right now.")
        end
        if !is_identity_transform
            error("$(typeof(xs)) with interpolate = true with a non-identity transform is not supported right now.")
        end
    end

    ni, nj = size(colors)
    pixels = _flat_pixels(colors)

    if is_regular_grid && is_identity_transform && (interpolate || is_xy_aligned)
        xy = _project_screen_px(pv, res, model, (first(xs), first(ys)))
        xymax = _project_screen_px(pv, res, model, (last(xs), last(ys)))
        w = xymax[1] - xy[1]
        h = xymax[2] - xy[2]
        WasmMakie.draw_image_scaled!(rctx, pixels, Int64(ni), Int64(nj),
                                     xy[1], xy[2], w, h, Bool(interpolate))
    else
        if ni + 1 != length(xs) || nj + 1 != length(ys)
            error("Error in conversion pipeline. xs and ys should have size ni+1, nj+1. Found: xs: $(length(xs)), ys: $(length(ys)), ni: $(ni), nj: $(nj)")
        end
        stride = ni + 1
        xys = Vector{NTuple{2,Float64}}(undef, stride * (nj + 1))
        for j in 0:nj, i in 1:stride
            xys[i + j * stride] = _project_screen_px(pv, res, model, (xs[i], ys[j + 1]))
        end
        WasmMakie.draw_rect_heatmap!(rctx, xys, Int64(ni), Int64(nj), pixels)
    end
    return
end

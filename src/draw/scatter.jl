# VENDORED (translated) from CairoMakie v0.15.11 — src/scatter.jl
# (draw_marker for Circle/Rect/BezierPath + draw_path/path_command).
# License: MIT (see VENDORED.md). Cairo→Canvas2D; divergences marked.
#
# Markers draw in a local unit frame: translate to the projected position,
# apply the 2×2 marker matrix (markersize/rotation/projection basis), then
# draw the unit shape (circle r=0.5 / rect 1×1 / encoded bezier path).
# WASM-DIVERGENCE: Cairo needs fill_preserve to keep the path for the stroke
# pass; canvas fill() keeps the path anyway, so plain fill + stroke matches.

# Encoded path commands (closed-world BezierPath representation):
# code 0 MoveTo(x,y) · 1 LineTo(x,y) · 2 CurveTo(c1x,c1y,c2x,c2y,x,y) ·
# 3 ClosePath · 4 EllipticalArc(cx,cy,r1,r2,angle,a1,a2) ·
# 5 QuadTo(cx,cy,x,y) — TrueType glyph outlines are conic
const PATH_MOVE = Int64(0)
const PATH_LINE = Int64(1)
const PATH_CURVE = Int64(2)
const PATH_CLOSE = Int64(3)
const PATH_ARC = Int64(4)
const PATH_QUAD = Int64(5)

const _PATH_NCOORDS = (2, 2, 6, 0, 7, 4)  # per code, index = code + 1

# Translated from CairoMakie draw_path/path_command.
function draw_path!(ctx, codes::Vector{Int64}, coords::Vector{Float64})
    j = 1
    for code in codes
        if code == PATH_MOVE
            move_to(ctx, coords[j], coords[j + 1])
        elseif code == PATH_LINE
            line_to(ctx, coords[j], coords[j + 1])
        elseif code == PATH_CURVE
            bezier_curve_to(ctx, coords[j], coords[j + 1], coords[j + 2],
                            coords[j + 3], coords[j + 4], coords[j + 5])
        elseif code == PATH_CLOSE
            close_path(ctx)
        elseif code == PATH_QUAD
            quadratic_curve_to(ctx, coords[j], coords[j + 1], coords[j + 2], coords[j + 3])
        elseif code == PATH_ARC
            cx = coords[j]; cy = coords[j + 1]
            r1 = coords[j + 2]; r2 = coords[j + 3]
            angle = coords[j + 4]; a1 = coords[j + 5]; a2 = coords[j + 6]
            save(ctx)
            translate(ctx, cx, cy)
            rotate(ctx, angle)
            scale_xy(ctx, 1.0, r2 / r1)
            arc(ctx, 0.0, 0.0, r1, a1, a2, a2 > a1 ? Int64(0) : Int64(1))
            restore(ctx)
        end
        j += _PATH_NCOORDS[code + 1]
    end
    return nothing
end

function _marker_frame!(ctx, x::Float64, y::Float64,
                        m11::Float64, m12::Float64, m21::Float64, m22::Float64)
    save(ctx)
    translate(ctx, x, y)
    transform(ctx, m11, m12, m21, m22, 0.0, 0.0)
    return nothing
end

# Fill under the marker transform, then RESTORE before stroking.
# WASM-DIVERGENCE (empirically calibrated against CairoMakie 0.15.11 output):
# the stroke pen is NOT scaled by the marker matrix — a strokewidth of 4 is a
# 4-device-px ring regardless of markersize. Canvas paths are committed in
# device space at construction time, so restoring first gives exactly that.
# Also: canvas IGNORES lineWidth = 0 (keeps the previous width — Cairo honors
# zero), so zero-width/invisible strokes must be skipped explicitly.
function _fill_stroke!(ctx, fr::Float64, fg::Float64, fb::Float64, fa::Float64,
                       sr::Float64, sg::Float64, sb::Float64, sa::Float64,
                       strokewidth::Float64)
    set_fill_rgba(ctx, 255.0 * fr, 255.0 * fg, 255.0 * fb, fa)
    fill_nonzero(ctx)
    restore(ctx)  # pops the _marker_frame! save — pen width is device-scaled
    if strokewidth > 0.0 && sa > 0.0
        set_line_width(ctx, strokewidth)
        set_stroke_rgba(ctx, 255.0 * sr, 255.0 * sg, 255.0 * sb, sa)
        stroke(ctx)
    end
    return nothing
end

"Circle marker (translated from CairoMakie draw_marker ::Type{<:Circle})."
function draw_marker_circle!(ctx, x::Float64, y::Float64,
                             m11::Float64, m12::Float64, m21::Float64, m22::Float64,
                             fr::Float64, fg::Float64, fb::Float64, fa::Float64,
                             sr::Float64, sg::Float64, sb::Float64, sa::Float64,
                             strokewidth::Float64)
    _marker_frame!(ctx, x, y, m11, m12, m21, m22)
    begin_path(ctx)
    arc(ctx, 0.0, 0.0, 0.5, 0.0, 2.0 * pi, Int64(0))
    _fill_stroke!(ctx, fr, fg, fb, fa, sr, sg, sb, sa, strokewidth)  # restores the marker frame
    return nothing
end

"Load an image-marker pixel buffer. Like upstream's one `marker_surf` per
scatter, the buffer is loaded ONCE per batch and blitted at every position —
per-pixel push commands for a large marker at every point would explode the
command stream (the billboard cow.png test: 96 markers × 160K pixels)."
function marker_image_buffer!(ctx, pixels::Vector{NTuple{4,Float64}}, w::Int64, h::Int64)
    img_buf_new(ctx, w, h)
    for k in 1:(w * h)
        r, g, b, a = pixels[k]
        img_buf_push_rgba(ctx, round(Int64, 255.0 * r), round(Int64, 255.0 * g),
                          round(Int64, 255.0 * b), round(Int64, 255.0 * a))
    end
    return nothing
end

"Image marker (translated from CairoMakie draw_marker ::Matrix{<:Colorant}):
blit the CURRENT image buffer (see `marker_image_buffer!`) centered in the
unit marker frame — upstream's scale(1/w, 1/h) + paint at (-w/2, -h/2).
Stroke is unused upstream."
function draw_marker_image!(ctx, x::Float64, y::Float64,
                            m11::Float64, m12::Float64, m21::Float64, m22::Float64,
                            w::Int64, h::Int64)
    _marker_frame!(ctx, x, y, m11, m12, m21, m22)
    set_image_smoothing(ctx, Int64(1))
    translate(ctx, -0.5, -0.5)
    scale_xy(ctx, 1.0 / w, 1.0 / h)
    draw_image_buf(ctx, 0.0, 0.0, Float64(w), Float64(h))
    restore(ctx)
    return nothing
end

"Rect marker (translated from CairoMakie draw_marker ::Type{<:Rect})."
function draw_marker_rect!(ctx, x::Float64, y::Float64,
                           m11::Float64, m12::Float64, m21::Float64, m22::Float64,
                           fr::Float64, fg::Float64, fb::Float64, fa::Float64,
                           sr::Float64, sg::Float64, sb::Float64, sa::Float64,
                           strokewidth::Float64)
    _marker_frame!(ctx, x, y, m11, m12, m21, m22)
    begin_path(ctx)
    rect(ctx, -0.5, -0.5, 1.0, 1.0)
    _fill_stroke!(ctx, fr, fg, fb, fa, sr, sg, sb, sa, strokewidth)  # restores the marker frame
    return nothing
end

"BezierPath marker (translated from CairoMakie draw_marker ::BezierPath)."
function draw_marker_path!(ctx, x::Float64, y::Float64,
                           m11::Float64, m12::Float64, m21::Float64, m22::Float64,
                           codes::Vector{Int64}, coords::Vector{Float64},
                           fr::Float64, fg::Float64, fb::Float64, fa::Float64,
                           sr::Float64, sg::Float64, sb::Float64, sa::Float64,
                           strokewidth::Float64)
    _marker_frame!(ctx, x, y, m11, m12, m21, m22)
    scale_xy(ctx, 1.0, -1.0)  # BezierPath y-up → canvas y-down (as CairoMakie)
    begin_path(ctx)
    draw_path!(ctx, codes, coords)
    _fill_stroke!(ctx, fr, fg, fb, fa, sr, sg, sb, sa, strokewidth)  # restores the marker frame
    return nothing
end

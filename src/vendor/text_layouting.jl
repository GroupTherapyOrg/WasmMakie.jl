# VENDORED from Makie v0.24.11 — src/layouting/text_layouting.jl
# (glyph_collection, the layout algorithm: per-char x accumulation, word
# wrap, \n line splitting, justification, h/v alignment, per-char rotation
# about the anchor). License: MIT (see VENDORED.md).
#
# WASM-DIVERGENCE (typed translation, structure preserved line-for-line
# where possible):
#   - extents come from the T-002 ExtentProvider (canvas measureText) instead
#     of FreeTypeAbstraction; `extent.ascender/descender` map to
#     font_ascent/−font_descent, `font.height/units_per_EM` to their sum
#   - one font + one scale per string (the static core's text surface);
#     attribute_per_char / per-char fonts dropped
#   - SubArray views → (start, stop) index ranges; Float32 → Float64;
#     Point3f origins → parallel xs/ys vectors; color attributes dropped
#     (the draw path owns color)
#   - halign/valign/justification pre-resolved to numbers by the caller
#     (`halign2num`/`valign2num` below mirror upstream; baseline valign and
#     automatic justification use -1.0 sentinels)

"Typed equivalent of Makie's GlyphCollection (single font/scale run)."
struct GlyphCollection
    glyphs::Vector{Int64}      # codepoints, '\n' entries retained (draw skips)
    origins_x::Vector{Float64} # per-glyph origin relative to the anchor, rotated
    origins_y::Vector{Float64}
    scale::Float64
    rotation::Float64          # radians, ccw (already applied to origins)
end

"Upstream halign2num: :left|:center|:right or a number → 0..1."
halign2num(h::Symbol) = h === :left ? 0.0 : h === :right ? 1.0 : 0.5
halign2num(h::Real) = Float64(h)

"Upstream valign2num: :top|:center|:bottom|:baseline or a number; baseline → -1.0 sentinel."
valign2num(v::Symbol) = v === :top ? 1.0 : v === :bottom ? 0.0 :
                        v === :baseline ? -1.0 : 0.5
valign2num(v::Real) = Float64(v)

"""
    glyph_collection!(p, ctx, cps, fam, weight, italic, fontscale_px,
                      halign, valign, lineheight_factor, justification,
                      rotation, word_wrap_width) -> GlyphCollection

Verbatim-structure translation of Makie `glyph_collection`. `halign` ∈ 0..1,
`valign` ∈ 0..1 or -1.0 (baseline), `justification` ∈ 0..1 or -1.0
(automatic → follows halign), `rotation` in radians, `word_wrap_width` ≤ 0
disables wrapping.
"""
function glyph_collection!(p, ctx, cps::Vector{Int64},
                           fam::Int64, weight::Int64, italic::Int64,
                           fontscale_px::Float64, halign::Float64, valign::Float64,
                           lineheight_factor::Float64, justification::Float64,
                           rotation::Float64, word_wrap_width::Float64)
    if isempty(cps)
        return GlyphCollection(Int64[], Float64[], Float64[], fontscale_px, rotation)
    end

    n = length(cps)
    scale = fontscale_px

    # charinfos (parallel vectors): char may be rewritten ' '→'\n' by wrapping
    chars = Vector{Int64}(undef, n)
    advances = Vector{Float64}(undef, n)
    ascenders = Vector{Float64}(undef, n)   # font-level, scaled
    descenders = Vector{Float64}(undef, n)  # negative, like FreeType descender
    lineheights = Vector{Float64}(undef, n)
    for i in 1:n
        g = glyph_extent!(p, ctx, cps[i], fam, weight, italic)
        chars[i] = cps[i]
        advances[i] = g.hadvance * scale
        ascenders[i] = g.font_ascent * scale
        descenders[i] = -g.font_descent * scale
        # upstream: font.height / units_per_EM * lineheight_factor * scale
        lineheights[i] = g.font_height * lineheight_factor * scale
    end

    # split into lines after every \n (upstream loop, views → ranges)
    line_start = Int64[]
    line_stop = Int64[]
    xs = Vector{Vector{Float64}}()
    push!(xs, Float64[])
    let
        last_line_start = 1
        last_space_local_idx = 0
        last_space_global_idx = 0
        x = 0.0
        for i in 1:n
            push!(xs[end], x)
            x += advances[i]

            if 0.0 < word_wrap_width < x && last_space_local_idx != 0 &&
                    ((chars[i] == Int64(' ') || chars[i] == Int64('\n')) || i == n)
                newline_offset = xs[end][last_space_local_idx + 1]
                moved = Float64[]
                for j in (last_space_local_idx + 1):length(xs[end])
                    push!(moved, xs[end][j] - newline_offset)
                end
                resize!(xs[end], last_space_local_idx)
                push!(xs, moved)
                push!(line_start, last_line_start)
                push!(line_stop, last_space_global_idx)
                last_line_start = last_space_global_idx + 1
                x = xs[end][end] + advances[i]
                chars[last_space_global_idx] = Int64('\n')
            end

            if chars[i] == Int64('\n')
                push!(xs, Float64[])
                push!(line_start, last_line_start)
                push!(line_stop, i)
                last_space_local_idx = 0
                last_line_start = i + 1
                x = 0.0
            elseif i == n
                push!(line_start, last_line_start)
                push!(line_stop, i)
            end

            if 0.0 < word_wrap_width && chars[i] == Int64(' ')
                last_space_local_idx = length(xs[end])
                last_space_global_idx = i
            end
        end
    end
    nlines = length(line_start)

    # linewidths: last origin + hadvance per line; trailing \n uses previous char
    linewidths = Vector{Float64}(undef, nlines)
    for li in 1:nlines
        lo = line_start[li]
        hi = line_stop[li]
        nchars = hi - lo + 1
        i = (nchars > 1 && chars[hi] == Int64('\n')) ? nchars - 1 : nchars
        linewidths[li] = xs[li][i] + advances[lo + i - 1]
    end

    maxwidth = 0.0
    for w in linewidths
        w > maxwidth && (maxwidth = w)
    end

    # justification shift (automatic = -1.0 sentinel → follows halign)
    float_justification = justification < 0.0 ? halign : justification
    for li in 1:nlines
        wd = maxwidth - linewidths[li]
        for j in eachindex(xs[li])
            xs[li][j] += wd * float_justification
        end
    end

    # per-line height = max char lineheight in the line
    line_h = Vector{Float64}(undef, nlines)
    for li in 1:nlines
        m = 0.0
        for i in line_start[li]:line_stop[li]
            lineheights[i] > m && (m = lineheights[i])
        end
        line_h[li] = m
    end

    # y per line: cumsum of -lineheights, first at 0 (upstream cumsum([0; ...]))
    ys = Vector{Float64}(undef, nlines)
    ys[1] = 0.0
    for li in 2:nlines
        ys[li] = ys[li - 1] - line_h[li]
    end

    # x alignment
    for li in 1:nlines
        for j in eachindex(xs[li])
            xs[li][j] -= halign * maxwidth
        end
    end

    # largest ascender of first line, largest descender (most negative) of last
    first_line_ascender = -Inf
    for i in line_start[1]:line_stop[1]
        ascenders[i] > first_line_ascender && (first_line_ascender = ascenders[i])
    end
    last_line_descender = Inf
    for i in line_start[nlines]:line_stop[nlines]
        descenders[i] < last_line_descender && (last_line_descender = descenders[i])
    end

    overall_height = first_line_ascender - ys[nlines] - last_line_descender

    # y alignment (baseline = -1.0 sentinel)
    if valign < 0.0
        for li in 1:nlines
            ys[li] = ys[li] - first_line_ascender + overall_height + last_line_descender
        end
    else
        for li in 1:nlines
            ys[li] = ys[li] - first_line_ascender + (1.0 - valign) * overall_height
        end
    end

    # rotate each char origin about the (0,0) anchor
    c = cos(rotation)
    s = sin(rotation)
    glyphs = Vector{Int64}(undef, n)
    ox = Vector{Float64}(undef, n)
    oy = Vector{Float64}(undef, n)
    k = 1
    for li in 1:nlines
        for (j, i) in enumerate(line_start[li]:line_stop[li])
            xj = xs[li][j]
            yj = ys[li]
            glyphs[k] = chars[i]
            ox[k] = c * xj - s * yj
            oy[k] = s * xj + c * yj
            k += 1
        end
    end

    return GlyphCollection(glyphs, ox, oy, scale, rotation)
end

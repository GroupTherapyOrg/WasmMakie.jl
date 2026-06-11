# T-002 — the measure_text-backed FontExtent provider.
#
# `glyph_extent!(provider, ctx, cp, fam, weight, italic)` returns per-glyph
# metrics NORMALIZED to one font-size unit (measured once at EXTENT_REF_SIZE,
# cached, scaled by the caller). This is the interface the vendored text
# layouting (T-003) consumes; the T-004 deterministic metric tables become a
# second provider behind the same call shape.
#
# Closed-world discipline: the cache is two parallel concrete Vectors with a
# packed-Int64 key and linear scan — tick labels and axis text touch a few
# dozen distinct glyphs, and Dict is off-limits in compiled core code (P5).
#
# Ctx-state caveat: a cache MISS issues set_font/text_buf/measure ops on the
# ctx (changing current font and text buffer); callers re-set their font
# before drawing — render paths already do. Cache behavior is deterministic,
# so host and wasm streams stay structurally EQUAL (same ops, same order);
# the RETURN values differ (RecordingCtx fixed ratios vs live measureText)
# until T-004 — layout must not feed measured values into draw coordinates
# before then.

"Per-glyph metrics, per font-size unit (multiply by size in px)."
struct GlyphExtent
    hadvance::Float64     # measureText().width
    ascent::Float64       # actualBoundingBoxAscent (ink, above baseline)
    descent::Float64      # actualBoundingBoxDescent (ink, below baseline)
    left::Float64         # actualBoundingBoxLeft (ink, left of origin)
    right::Float64        # actualBoundingBoxRight (ink, right of origin)
    font_ascent::Float64  # fontBoundingBoxAscent — FreeType ascender analog
    font_descent::Float64 # fontBoundingBoxDescent — −descender analog
    font_height::Float64  # FreeType height/units_per_EM (Makie lineheight base);
                          # measured mode approximates with ascent+descent
end

"Reference pixel size glyphs are measured at (metrics scale linearly)."
const EXTENT_REF_SIZE = 64.0

mutable struct ExtentProvider
    keys::Vector{Int64}
    extents::Vector{GlyphExtent}
end

ExtentProvider() = ExtentProvider(Int64[], GlyphExtent[])

# codepoint (21 bits) | fam<<24 | weight<<36 | italic<<52
_extent_key(cp::Int64, fam::Int64, weight::Int64, italic::Int64) =
    cp | (fam << 24) | (weight << 36) | (italic << 52)

"""
    glyph_extent!(p::ExtentProvider, ctx, cp, fam, weight, italic) -> GlyphExtent

The cached per-glyph extent (normalized per font-size unit). Cache miss
measures through `ctx` at `EXTENT_REF_SIZE` — see the ctx-state caveat above.
"""
function glyph_extent!(p::ExtentProvider, ctx, cp::Int64, fam::Int64,
                       weight::Int64, italic::Int64)
    key = _extent_key(cp, fam, weight, italic)
    n = length(p.keys)
    i = 1
    while i <= n
        if p.keys[i] == key
            return p.extents[i]
        end
        i += 1
    end
    set_font(ctx, fam, EXTENT_REF_SIZE, weight, italic)
    text_buf_clear(ctx)
    text_buf_push(ctx, cp)
    w = measure_text_buf_width(ctx)
    a = measure_text_buf_ascent(ctx)
    d = measure_text_buf_descent(ctx)
    l = measure_text_buf_left(ctx)
    r = measure_text_buf_right(ctx)
    fa = measure_text_buf_font_ascent(ctx)
    fd = measure_text_buf_font_descent(ctx)
    g = GlyphExtent(w / EXTENT_REF_SIZE, a / EXTENT_REF_SIZE, d / EXTENT_REF_SIZE,
                    l / EXTENT_REF_SIZE, r / EXTENT_REF_SIZE,
                    fa / EXTENT_REF_SIZE, fd / EXTENT_REF_SIZE,
                    (fa + fd) / EXTENT_REF_SIZE)
    push!(p.keys, key)
    push!(p.extents, g)
    return g
end

"""
    text_advance!(p, ctx, cps, size, fam, weight, italic) -> Float64

Sum of cached per-glyph advances scaled to `size`, in px. NOTE: per-glyph
sums carry no kerning — canvas `measureText` cannot expose pairs. The T-004
FreeType tables add kerning; Makie's own layouting is per-glyph too.
"""
function text_advance!(p::ExtentProvider, ctx, cps::Vector{Int64}, size::Float64,
                       fam::Int64, weight::Int64, italic::Int64)
    total = 0.0
    for cp in cps
        total += glyph_extent!(p, ctx, cp, fam, weight, italic).hadvance
    end
    return total * size
end

"""
    string_extent!(p, ctx, cps, size, fam, weight, italic)
        -> (width, ascent, descent)

Tight line box for one run of codepoints at `size` px: summed advances ×
size, max ink ascent/descent × size.
"""
function string_extent!(p::ExtentProvider, ctx, cps::Vector{Int64}, size::Float64,
                        fam::Int64, weight::Int64, italic::Int64)
    w = 0.0
    asc = 0.0
    desc = 0.0
    for cp in cps
        g = glyph_extent!(p, ctx, cp, fam, weight, italic)
        w += g.hadvance
        g.ascent > asc && (asc = g.ascent)
        g.descent > desc && (desc = g.descent)
    end
    return (w * size, asc * size, desc * size)
end

# T-004 generator — extract FreeType per-em metrics for the bundled fonts
# and emit src/vendor/font_metrics.jl (const tables compiled into wasm).
#
#   julia +1.12 --project=CanvasMakie/test reftests/gen_font_metrics.jl
#
# Field mapping mirrors Makie's GlyphExtent(font, char) exactly
# (src/types.jl): ink bbox from get_extent, ascender/descender(font),
# lineheight base font.height/units_per_EM. Canvas-semantics signs:
# left = −leftinkbound (actualBoundingBoxLeft), descent = −bottominkbound.
import Makie
const FreeTypeAbstraction = Makie.FreeTypeAbstraction
const FTFont = FreeTypeAbstraction.FTFont

const FONTS_DIR = joinpath(dirname(@__DIR__), "assets", "fonts")
const OUT = joinpath(dirname(@__DIR__), "src", "vendor", "font_metrics.jl")

const FACES = [
    ("TeXGyreHerosMakie-Regular.otf", "TGH Regular (fam 0, w<700, upright)"),
    ("TeXGyreHerosMakie-Bold.otf", "TGH Bold (fam 0, w≥700, upright)"),
    ("TeXGyreHerosMakie-Italic.otf", "TGH Italic (fam 0, w<700, italic)"),
    ("TeXGyreHerosMakie-BoldItalic.otf", "TGH BoldItalic (fam 0, w≥700, italic)"),
    ("DejaVuSans.ttf", "DejaVu Sans (fam 1)"),
]

# tick/axis-label charset: printable ASCII + MINUS SIGN + MULTIPLICATION SIGN
const CPS = vcat(collect(32:126), [0x2212, 0x00D7])

io = IOBuffer()
println(io, """
# VENDORED (generated) from the bundled fonts via FreeTypeAbstraction —
# regenerate with reftests/gen_font_metrics.jl. License: fonts under
# assets/fonts/LICENSES.md; tables are derived data.
#
# T-004 deterministic metric tables: per-em glyph metrics for the 5 bundled
# faces over the tick-label charset (ASCII 32–126 + − U+2212 + × U+00D7).
# `TableExtents` serves these through the same `glyph_extent!` interface the
# vendored layouting consumes — host and wasm read the SAME consts, so text
# layout is bit-identical (the measureText provider stays available for
# arbitrary glyphs; unknown codepoints fall back to '?').
#
# Per-glyph tuple: (hadvance, ink_ascent, ink_descent, ink_left, ink_right)
# Per-face tuple:  (font_ascent, font_descent, font_height)

"Charset size per face block in GLYPH_METRICS."
const METRIC_NCPS = Int64($(length(CPS)))
""")

# face-level metrics
println(io, "const FACE_METRICS = NTuple{3,Float64}[")
glyph_rows = Vector{String}[]
for (file, desc) in FACES
    ft = FTFont(joinpath(FONTS_DIR, file))
    fa = Float64(FreeTypeAbstraction.ascender(ft))
    fd = -Float64(FreeTypeAbstraction.descender(ft))   # store positive
    fh = Float64(ft.height / ft.units_per_EM)
    println(io, "    ($fa, $fd, $fh),  # $desc")
    rows = String[]
    for cp in CPS
        ext = FreeTypeAbstraction.get_extent(ft, Char(cp))
        ha = Float64(FreeTypeAbstraction.hadvance(ext))
        l = Float64(FreeTypeAbstraction.leftinkbound(ext))
        r = Float64(FreeTypeAbstraction.rightinkbound(ext))
        t = Float64(FreeTypeAbstraction.topinkbound(ext))
        b = Float64(FreeTypeAbstraction.bottominkbound(ext))
        push!(rows, "    ($ha, $t, $(-b), $(-l), $r),")
    end
    push!(glyph_rows, rows)
end
println(io, "]")
println(io)
println(io, "const GLYPH_METRICS = NTuple{5,Float64}[")
for (fi, rows) in enumerate(glyph_rows)
    println(io, "    # face $fi: $(FACES[fi][2])")
    for row in rows
        println(io, row)
    end
end
println(io, "]")

println(io, """

"1-based charset index for `cp`; unknown codepoints map to '?' (Makie-style fallback, documented)."
function _metric_cp_index(cp::Int64)
    32 <= cp <= 126 && return cp - 31
    cp == 0x2212 && return Int64(96)
    cp == 0x00D7 && return Int64(97)
    return Int64(63 - 31)  # '?'
end

"1-based face index from the set_font triple; fam ≥ 2 (monospace) falls back to face 1."
function _metric_face_index(fam::Int64, weight::Int64, italic::Int64)
    fam == 1 && return Int64(5)
    bold = weight >= 700
    it = italic != 0
    bold && it && return Int64(4)
    it && return Int64(3)
    bold && return Int64(2)
    return Int64(1)
end

\"\"\"
    TableExtents()

The deterministic extent provider (T-004): serves the compiled-in FreeType
tables through the same `glyph_extent!` interface as `ExtentProvider`, with
no ctx traffic — host and wasm layouts are bit-identical.
\"\"\"
struct TableExtents end

function glyph_extent!(::TableExtents, ctx, cp::Int64, fam::Int64,
                       weight::Int64, italic::Int64)
    fi = _metric_face_index(fam, weight, italic)
    ci = _metric_cp_index(cp)
    g = GLYPH_METRICS[(fi - 1) * METRIC_NCPS + ci]
    f = FACE_METRICS[fi]
    return GlyphExtent(g[1], g[2], g[3], g[4], g[5], f[1], f[2], f[3])
end
""")

write(OUT, String(take!(io)))
println("wrote ", OUT)

# sanity prints
ft = FTFont(joinpath(FONTS_DIR, "TeXGyreHerosMakie-Regular.otf"))
println("TGH M advance/em: ", FreeTypeAbstraction.hadvance(FreeTypeAbstraction.get_extent(ft, 'M')))
println("TGH ascender: ", FreeTypeAbstraction.ascender(ft), " descender: ", FreeTypeAbstraction.descender(ft),
        " height/upem: ", ft.height / ft.units_per_EM)

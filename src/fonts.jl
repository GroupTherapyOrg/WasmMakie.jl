# Bundled fonts (T-001) — Makie's default faces, copied verbatim from
# Makie v0.24.11 assets/fonts/ (licenses: assets/fonts/LICENSES.md; TeX Gyre
# Heros under the GUST Font License, DejaVu under the Bitstream Vera license).
#
# Family indices in the canvas op `set_font(fam, …)` and the glue's `S.fonts`
# table:
#   0 = "TeX Gyre Heros Makie"  (Makie's default; 4 faces via weight/style)
#   1 = "DejaVu Sans"           (Makie's wide-coverage fallback)
#   2 = monospace               (generic; no bundled face)
#
# `canvas2d_load_fonts(faces)` in the glue (ops.jl) registers these via
# FontFace so `fill_text`/`measure_text` use IDENTICAL fonts in every host —
# hosts pass `font_faces_json()` output (self-contained data: URLs) or their
# own hosted URLs in the same shape.

const FONTS_DIR = joinpath(dirname(@__DIR__), "assets", "fonts")

"(family, weight, style, filename) for every bundled face."
const FONT_FACES = [
    ("TeX Gyre Heros Makie", 400, "normal", "TeXGyreHerosMakie-Regular.otf"),
    ("TeX Gyre Heros Makie", 700, "normal", "TeXGyreHerosMakie-Bold.otf"),
    ("TeX Gyre Heros Makie", 400, "italic", "TeXGyreHerosMakie-Italic.otf"),
    ("TeX Gyre Heros Makie", 700, "italic", "TeXGyreHerosMakie-BoldItalic.otf"),
    ("DejaVu Sans", 400, "normal", "DejaVuSans.ttf"),
]

_font_mime(file::AbstractString) = endswith(file, ".otf") ? "font/otf" : "font/ttf"

# Local base64 (RFC 4648) so WasmMakie stays dependency-free — adding the
# Base64 stdlib to [deps] changes the precompile image and re-triggers the
# known Julia 1.12 GC segfault at the C-002 subprocess-oracle testset.
const _B64 = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function _base64encode(bytes::Vector{UInt8})
    n = length(bytes)
    out = Vector{UInt8}(undef, 4 * cld(n, 3))
    o = 1
    i = 1
    while i + 2 <= n
        v = (UInt32(bytes[i]) << 16) | (UInt32(bytes[i + 1]) << 8) | UInt32(bytes[i + 2])
        out[o] = _B64[((v >> 18) & 0x3f) + 1]; out[o + 1] = _B64[((v >> 12) & 0x3f) + 1]
        out[o + 2] = _B64[((v >> 6) & 0x3f) + 1]; out[o + 3] = _B64[(v & 0x3f) + 1]
        o += 4; i += 3
    end
    rem = n - i + 1
    if rem == 1
        v = UInt32(bytes[i]) << 16
        out[o] = _B64[((v >> 18) & 0x3f) + 1]; out[o + 1] = _B64[((v >> 12) & 0x3f) + 1]
        out[o + 2] = UInt8('='); out[o + 3] = UInt8('=')
    elseif rem == 2
        v = (UInt32(bytes[i]) << 16) | (UInt32(bytes[i + 1]) << 8)
        out[o] = _B64[((v >> 18) & 0x3f) + 1]; out[o + 1] = _B64[((v >> 12) & 0x3f) + 1]
        out[o + 2] = _B64[((v >> 6) & 0x3f) + 1]; out[o + 3] = UInt8('=')
    end
    return String(out)
end

"""
    font_faces_json() -> String

The bundled faces as a JSON array of `{family, weight, style, url}` with
self-contained base64 `data:` URLs — the argument shape `canvas2d_load_fonts`
expects. Hosts that serve font files themselves can build the same shape with
plain URLs instead.
"""
function font_faces_json()
    entries = String[]
    for (family, weight, style, file) in FONT_FACES
        bytes = read(joinpath(FONTS_DIR, file))
        b64 = _base64encode(bytes)
        url = "data:$(_font_mime(file));base64,$(b64)"
        push!(entries, "{\"family\":\"$(family)\",\"weight\":$(weight)," *
                       "\"style\":\"$(style)\",\"url\":\"$(url)\"}")
    end
    return "[" * join(entries, ",") * "]"
end

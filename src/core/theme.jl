# VENDORED from Makie v0.24.11 — src/theming.jl (MAKIE_DEFAULT_THEME +
# wong_colors). License: MIT (see VENDORED.md).
#
# The static core has no theme Dict — Makie's defaults become typed constants
# (closed-world discipline). Parity with the live Makie theme is asserted in
# CanvasMakie's test suite, which has both packages loaded.

const THEME_SIZE = (600.0, 450.0)            # 4/3 aspect ratio
const THEME_BACKGROUNDCOLOR = (1.0, 1.0, 1.0, 1.0)  # :white
const THEME_TEXTCOLOR = (0.0, 0.0, 0.0, 1.0)        # :black
const THEME_FONTSIZE = 14.0
const THEME_FONT_REGULAR = "TeX Gyre Heros Makie"
const THEME_FIGURE_PADDING = 16.0
const THEME_ROWGAP = 18.0
const THEME_COLGAP = 18.0
const THEME_MARKERSIZE = 9.0
const THEME_LINEWIDTH = 1.5
const THEME_LINECAP = Int64(0)               # :butt
const THEME_JOINSTYLE = Int64(0)             # :miter
const THEME_MITER_LIMIT_ANGLE = pi / 3
const THEME_PATCHCOLOR = (0.4, 0.4, 0.4, 1.0)
const THEME_COLORMAP = :viridis

# Wong palette (vendored from wong_colors): the default color cycle.
const WONG_COLORS = (
    (0.0 / 255, 114.0 / 255, 178.0 / 255, 1.0),  # blue
    (230.0 / 255, 159.0 / 255, 0.0 / 255, 1.0),  # orange
    (0.0 / 255, 158.0 / 255, 115.0 / 255, 1.0),  # green
    (204.0 / 255, 121.0 / 255, 167.0 / 255, 1.0),# reddish purple
    (86.0 / 255, 180.0 / 255, 233.0 / 255, 1.0), # sky blue
    (213.0 / 255, 94.0 / 255, 0.0 / 255, 1.0),   # vermilion
    (240.0 / 255, 228.0 / 255, 66.0 / 255, 1.0), # yellow
)

"Color-cycle lookup: 1-based plot index → Wong palette color (wraps mod 7)."
function cycle_color(i::Int64)::NTuple{4,Float64}
    return WONG_COLORS[mod1(i, 7)]
end

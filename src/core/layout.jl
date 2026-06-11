# VENDORED (translated subset) from GridLayoutBase v0.9.2 — src/gridlayout.jl
# (compute_rowcols + compute_col_row_sizes solver math). License: MIT.
#
# WASM-DIVERGENCE (the plan's anticipated split): the solver MATH is
# translated; the Observable/LayoutObservables protocol around it is replaced
# by plain arguments. Supported subset: Inside and Outside(padding) align
# modes, Fixed/Relative/Auto sizes (Auto with weights), Fixed added gaps,
# full protrusion negotiation. Mixed alignmode, Aspect sizes, and
# equalprotrusiongaps are out of scope until the reference burn-down needs
# them. Parity vs live GridLayoutBase is asserted through Makie figures in
# CanvasMakie's tests.

const SIZE_AUTO = Int64(0)
const SIZE_FIXED = Int64(1)
const SIZE_RELATIVE = Int64(2)

"Fixed(px) / Relative(fraction) / Auto(weight) — GridLayoutBase's ContentSize as a tagged union."
struct SizeSpec
    kind::Int64
    value::Float64   # px for FIXED, fraction for RELATIVE, weight for AUTO
end
auto_size() = SizeSpec(SIZE_AUTO, 1.0)
fixed_size(px::Float64) = SizeSpec(SIZE_FIXED, px)
relative_size(f::Float64) = SizeSpec(SIZE_RELATIVE, f)

"Per-content protrusions: how far decorations stick out of the inner rect."
struct Protrusions
    l::Float64
    r::Float64
    t::Float64
    b::Float64
end
Protrusions() = Protrusions(0.0, 0.0, 0.0, 0.0)

# Translated from GridLayoutBase compute_col_row_sizes (one axis).
function _sizes_1d(space::Float64, specs::Vector{SizeSpec})
    n = length(specs)
    out = Vector{Float64}(undef, n)
    fixed_sum = 0.0
    rel_sum = 0.0
    auto_weight_sum = 0.0
    for s in specs
        if s.kind == SIZE_FIXED
            fixed_sum += s.value
        elseif s.kind == SIZE_RELATIVE
            rel_sum += s.value * space
        else
            auto_weight_sum += s.value
        end
    end
    remaining = space - fixed_sum - rel_sum
    for (i, s) in enumerate(specs)
        out[i] = s.kind == SIZE_FIXED ? s.value :
                 s.kind == SIZE_RELATIVE ? s.value * space :
                 auto_weight_sum > 0.0 ? remaining * (s.value / auto_weight_sum) : 0.0
    end
    return out
end

"""
    solve_grid(x, y, w, h, nrows, ncols, prots, rowsizes, colsizes,
               rowgap, colgap; outside_pad = 0.0) -> Vector{Rect2}

Solve the grid inside the (y-down, device-px) box `(x, y, w, h)`. `prots` is
one `Protrusions` per cell, row-major (`(r-1)*ncols + c`). With
`outside_pad > 0` the Outside(pad) align mode applies: the box shrinks by the
padding and protrusions live inside that padding (Makie Figure semantics);
otherwise Inside (protrusions consume interior space).

Returns the INNER rect per cell, row-major, in y-down device coordinates
(row 1 at the top, matching the canvas frame the draw layer uses).
"""
function solve_grid(x::Float64, y::Float64, w::Float64, h::Float64,
                    nrows::Int64, ncols::Int64, prots::Vector{Protrusions},
                    rowsizes::Vector{SizeSpec}, colsizes::Vector{SizeSpec},
                    rowgap::Float64, colgap::Float64; outside_pad::Float64 = 0.0)
    outside = outside_pad > 0.0
    cx = x + outside_pad
    cy = y + outside_pad
    cw = w - 2.0 * outside_pad
    ch = h - 2.0 * outside_pad

    at(r, c) = prots[(r - 1) * ncols + c]
    # per-column/row protrusion maxima (translated from _compute_maxgrid)
    L = [maximum(at(r, c).l for r in 1:nrows) for c in 1:ncols]
    R = [maximum(at(r, c).r for r in 1:nrows) for c in 1:ncols]
    T = [maximum(at(r, c).t for c in 1:ncols) for r in 1:nrows]
    B = [maximum(at(r, c).b for c in 1:ncols) for r in 1:nrows]

    # gaps between tracks host the adjoining protrusions
    colgaps_p = [L[c + 1] + R[c] for c in 1:(ncols - 1)]
    rowgaps_p = [T[r + 1] + B[r] for r in 1:(nrows - 1)]
    sumcolgaps = isempty(colgaps_p) ? 0.0 : sum(colgaps_p)
    sumrowgaps = isempty(rowgaps_p) ? 0.0 : sum(rowgaps_p)

    # Upstream semantics: Outside subtracts the edge protrusions (they live
    # inside the padded content box); Inside lets them OVERFLOW the bbox.
    remaining_w = outside ? cw - sumcolgaps - L[1] - R[end] : cw - sumcolgaps
    remaining_h = outside ? ch - sumrowgaps - T[1] - B[end] : ch - sumrowgaps

    space_cols = remaining_w - colgap * (ncols - 1)
    space_rows = remaining_h - rowgap * (nrows - 1)

    colwidths = max.(_sizes_1d(space_cols, colsizes), 1.0)
    rowheights = max.(_sizes_1d(space_rows, rowsizes), 1.0)

    # alignment (upstream tail): when the grid doesn't fill its box, the
    # default :center halign/valign shifts it by half the slack
    sumaddedcol = colgap * (ncols - 1)
    sumaddedrow = rowgap * (nrows - 1)
    gridwidth = sum(colwidths) + sumcolgaps + sumaddedcol + (outside ? L[1] + R[end] : 0.0)
    gridheight = sum(rowheights) + sumrowgaps + sumaddedrow + (outside ? T[1] + B[end] : 0.0)
    xadjust = 0.5 * (cw - gridwidth)
    yadjust = 0.5 * (ch - gridheight)

    rects = Vector{Rect2}(undef, nrows * ncols)
    ypos = (outside ? cy + T[1] : cy) + yadjust
    xstart = (outside ? cx + L[1] : cx) + xadjust
    for r in 1:nrows
        xpos = xstart
        for c in 1:ncols
            rects[(r - 1) * ncols + c] = Rect2(xpos, ypos, colwidths[c], rowheights[r])
            if c < ncols
                xpos += colwidths[c] + colgaps_p[c] + colgap
            end
        end
        if r < nrows
            ypos += rowheights[r] + rowgaps_p[r] + rowgap
        end
    end
    return rects
end

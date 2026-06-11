# VENDORED (translated) from Contour.jl v0.6 — src/Contour.jl +
# src/interpolate.jl (marching squares: cell classification, ambiguous-case
# bilinear disambiguation, chase/trace with loopback detection). License:
# MIT (see VENDORED.md).
#
# WASM-DIVERGENCE (typed translation, algorithm preserved):
#   - `Dict{Tuple{Int,Int},UInt8}` cell store → DENSE Vector{UInt8} over the
#     (nx−1)×(ny−1) cell grid (0 = no crossing; consumed cells zeroed) —
#     Dict is banned in compiled core paths (P5), and dense is faster here
#   - z as flat column-major Vector{Float64} + nx/ny (Matrix construction
#     fails wasm validation, WTGAP 3aaa51b9a688)
#   - `next_map`/`next_edge` tuple-of-tuples indexing → explicit if-chains
#   - Curve2/ContourLevel wrappers → plain Vector{Vector{NTuple{2,Float64}}}

const CT_N = UInt8(1)
const CT_S = UInt8(2)
const CT_E = UInt8(4)
const CT_W = UInt8(8)
const CT_NS = CT_N | CT_S
const CT_NE = CT_N | CT_E
const CT_NW = CT_N | CT_W
const CT_SE = CT_S | CT_E
const CT_SW = CT_S | CT_W
const CT_EW = CT_E | CT_W
const CT_NWSE = CT_NW | 0x10  # ambiguous
const CT_NESW = CT_NE | 0x10  # ambiguous

# edge_LUT (case 1..14, cases 5/10 handled separately)
function _edge_lut(case::UInt8)
    case == 0x01 && return CT_SW
    case == 0x02 && return CT_SE
    case == 0x03 && return CT_EW
    case == 0x04 && return CT_NE
    case == 0x06 && return CT_NS
    case == 0x07 && return CT_NW
    case == 0x08 && return CT_NW
    case == 0x09 && return CT_NS
    case == 0x0b && return CT_NE
    case == 0x0c && return CT_EW
    case == 0x0d && return CT_SE
    case == 0x0e && return CT_SW
    return 0x00
end

@inline _zat(z::Vector{Float64}, nx::Int64, xi::Int64, yi::Int64) = z[xi + (yi - 1) * nx]
@inline _cellkey(nx::Int64, xi::Int64, yi::Int64) = xi + (yi - 1) * (nx - 1)

"Classify every cell for level `h` into a dense cell array (0 = no crossing)."
function _get_level_cells(z::Vector{Float64}, nx::Int64, ny::Int64, h::Float64)
    cells = zeros(UInt8, (nx - 1) * (ny - 1))
    n = Int64(0)
    for yi in 1:(ny - 1)
        for xi in 1:(nx - 1)
            z1 = _zat(z, nx, xi, yi)
            z2 = _zat(z, nx, xi + 1, yi)
            z3 = _zat(z, nx, xi + 1, yi + 1)
            z4 = _zat(z, nx, xi, yi + 1)
            case = z1 > h ? 0x01 : 0x00
            z2 > h && (case |= 0x02)
            z3 > h && (case |= 0x04)
            z4 > h && (case |= 0x08)
            (case == 0x00 || case == 0x0f) && continue
            if case == 0x05
                cells[_cellkey(nx, xi, yi)] = 0.25 * (z1 + z2 + z3 + z4) >= h ? CT_NWSE : CT_NESW
            elseif case == 0x0a
                cells[_cellkey(nx, xi, yi)] = 0.25 * (z1 + z2 + z3 + z4) >= h ? CT_NESW : CT_NWSE
            else
                cells[_cellkey(nx, xi, yi)] = _edge_lut(case)
            end
            n += 1
        end
    end
    return cells, n
end

"Pop the crossing for `entry_edge` from the cell (ambiguous cells keep their other half)."
function _get_next_edge!(cells::Vector{UInt8}, key::Int64, entry_edge::UInt8)
    cell = cells[key]
    cells[key] = 0x00
    if cell == CT_NWSE
        if entry_edge == CT_N || entry_edge == CT_W
            cells[key] = CT_SE
            cell = CT_NW
        else
            cells[key] = CT_NW
            cell = CT_SE
        end
    elseif cell == CT_NESW
        if entry_edge == CT_N || entry_edge == CT_E
            cells[key] = CT_SW
            cell = CT_NE
        else
            cells[key] = CT_NE
            cell = CT_SW
        end
    end
    return cell ⊻ entry_edge
end

"Step to the neighboring cell across `edge`; returns (xi, yi, next_entry_edge)."
@inline function _advance_edge(xi::Int64, yi::Int64, edge::UInt8)
    edge == CT_N && return xi, yi + 1, CT_S
    edge == CT_S && return xi, yi - 1, CT_N
    edge == CT_E && return xi + 1, yi, CT_W
    return xi - 1, yi, CT_E   # W
end

@inline function _get_first_crossing(cell::UInt8)
    cell == CT_NWSE && return CT_NW
    cell == CT_NESW && return CT_NE
    return cell
end

"Linear interpolation of the crossing point on `edge` of cell (xi, yi)."
function _interpolate_crossing(xs::Vector{Float64}, ys::Vector{Float64},
                               z::Vector{Float64}, nx::Int64, h::Float64,
                               xi::Int64, yi::Int64, edge::UInt8)
    if edge == CT_W
        za = _zat(z, nx, xi, yi)
        zb = _zat(z, nx, xi, yi + 1)
        return (xs[xi], ys[yi] + (ys[yi + 1] - ys[yi]) * (h - za) / (zb - za))
    elseif edge == CT_E
        za = _zat(z, nx, xi + 1, yi)
        zb = _zat(z, nx, xi + 1, yi + 1)
        return (xs[xi + 1], ys[yi] + (ys[yi + 1] - ys[yi]) * (h - za) / (zb - za))
    elseif edge == CT_N
        za = _zat(z, nx, xi, yi + 1)
        zb = _zat(z, nx, xi + 1, yi + 1)
        return (xs[xi] + (xs[xi + 1] - xs[xi]) * (h - za) / (zb - za), ys[yi + 1])
    else  # S
        za = _zat(z, nx, xi, yi)
        zb = _zat(z, nx, xi + 1, yi)
        return (xs[xi] + (xs[xi + 1] - xs[xi]) * (h - za) / (zb - za), ys[yi])
    end
end

"Follow a contour from (xi, yi)/entry_edge until boundary or closure; returns end cell."
function _chase!(cells::Vector{UInt8}, curve::Vector{NTuple{2,Float64}},
                 xs::Vector{Float64}, ys::Vector{Float64}, z::Vector{Float64},
                 nx::Int64, ny::Int64, h::Float64,
                 sxi::Int64, syi::Int64, entry_edge::UInt8)
    xi = sxi
    yi = syi
    loopback_edge = entry_edge
    while true
        exit_edge = _get_next_edge!(cells, _cellkey(nx, xi, yi), entry_edge)
        push!(curve, _interpolate_crossing(xs, ys, z, nx, h, xi, yi, exit_edge))
        xi, yi, entry_edge = _advance_edge(xi, yi, exit_edge)
        inside = 1 <= xi <= nx - 1 && 1 <= yi <= ny - 1
        if !((xi != sxi || yi != syi || entry_edge != loopback_edge) && inside)
            break
        end
    end
    return xi, yi
end

"""
    contour_lines(xs, ys, z_flat, nx, ny, h) -> Vector{Vector{NTuple{2,Float64}}}

All isolines of the (flat column-major) grid `z` at level `h`
(Contour.jl `trace_contour`, typed translation).
"""
function contour_lines(xs::Vector{Float64}, ys::Vector{Float64},
                       z::Vector{Float64}, nx::Int64, ny::Int64, h::Float64)
    cells, nleft = _get_level_cells(z, nx, ny, h)
    out = Vector{Vector{NTuple{2,Float64}}}()
    cursor = 1
    ncells = length(cells)
    while nleft > 0
        while cursor <= ncells && cells[cursor] == 0x00
            cursor += 1
        end
        cursor > ncells && break
        # cell coordinates from the linear key
        key = cursor - 1
        xi = Int64(key % (nx - 1)) + 1
        yi = Int64(div(key, nx - 1)) + 1
        cell = cells[cursor]
        crossing = _get_first_crossing(cell)
        starting_edge = UInt8(0x01) << trailing_zeros(crossing)

        curve = NTuple{2,Float64}[]
        push!(curve, _interpolate_crossing(xs, ys, z, nx, h, xi, yi, starting_edge))
        exi, eyi = _chase!(cells, curve, xs, ys, z, nx, ny, h, xi, yi, starting_edge)

        if exi == xi && eyi == yi
            push!(out, curve)
        else
            nxi, nyi, sedge = _advance_edge(xi, yi, starting_edge)
            if 1 <= nxi <= nx - 1 && 1 <= nyi <= ny - 1 && cells[_cellkey(nx, nxi, nyi)] != 0x00
                reverse!(curve)
                _chase!(cells, curve, xs, ys, z, nx, ny, h, nxi, nyi, sedge)
            end
            push!(out, curve)
        end
        # recount consumed cells lazily: advance is cheap, recount nleft
        nleft = 0
        for c in cells
            c != 0x00 && (nleft += 1)
        end
    end
    return out
end

"Contour.jl `contourlevels`: n evenly spaced interior levels."
function contourlevels(zmin::Float64, zmax::Float64, n::Int64)
    dz = (zmax - zmin) / Float64(n + 1)
    out = Vector{Float64}(undef, n)
    for i in 1:n
        out[i] = zmin + dz * Float64(i)
    end
    return out
end

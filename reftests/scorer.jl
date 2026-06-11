# VENDORED from Makie.jl (master, 2026-06) — ReferenceTests/src/compare_media.jl
# License: MIT (see VENDORED.md). Divergences marked WASM-DIVERGENCE.
#
# The reference-image scorer: images are split into ~30×30-px tiles; per-pixel
# Euclidean distance in RGB(A) is averaged per tile; the score is the MAX tile
# mean (localized-error sensitive). CairoMakie's suite passes at threshold
# 0.05 — that is our host_refpass gate too.
#
# WASM-DIVERGENCE (tooling, not target): media loading uses PNGFiles directly
# instead of FileIO/ImageIO (no video path — we score stills only, videos are
# out of plan scope), and directory scoring returns a refpass NamedTuple and
# writes scores.tsv / missing_files.txt / new_files.txt like upstream CI.
module RefScorer

using PNGFiles
using ColorTypes
using FixedPointNumbers
using Statistics
import Downloads
import Tar

export compare_images, compare_media, score_directory, fetch_reference_images

const RGBf = RGB{Float32}
const RGBAf = RGBA{Float32}

rgbaf_convert(x::AbstractMatrix{<:Union{RGB,RGBA}}) = convert(Matrix{RGBAf}, x)

function compare_images(a::AbstractMatrix{<:Union{RGB,RGBA}}, b::AbstractMatrix{<:Union{RGB,RGBA}})
    a = rgbaf_convert(a)
    b = rgbaf_convert(b)

    if size(a) != size(b)
        @warn "images don't have the same size, difference will be Inf"
        return Inf
    end

    approx_tile_size_px = 30

    range_dim1 = round.(Int, range(0, size(a, 1), length = ceil(Int, size(a, 1) / approx_tile_size_px)))
    range_dim2 = round.(Int, range(0, size(a, 2), length = ceil(Int, size(a, 2) / approx_tile_size_px)))

    boundary_iter(boundaries) = zip(boundaries[1:(end - 1)] .+ 1, boundaries[2:end])

    _norm(rgb1::RGBf, rgb2::RGBf) = sqrt(sum(((rgb1.r - rgb2.r)^2, (rgb1.g - rgb2.g)^2, (rgb1.b - rgb2.b)^2)))
    _norm(rgba1::RGBAf, rgba2::RGBAf) = sqrt(sum(((rgba1.r - rgba2.r)^2, (rgba1.g - rgba2.g)^2, (rgba1.b - rgba2.b)^2, (rgba1.alpha - rgba2.alpha)^2)))

    # compute the difference score as the maximum of the mean squared differences over the color
    # values of tiles over the image. using tiles is a simple way to increase the local sensitivity
    # without directly going to pixel-based comparison
    # it also makes the scores more comparable between reference images of different sizes, because the same
    # local differences would be normed to different mean scores if the images have different numbers of pixels
    return maximum(Iterators.product(boundary_iter(range_dim1), boundary_iter(range_dim2))) do ((mi1, ma1), (mi2, ma2))
        @views mean(_norm.(a[mi1:ma1, mi2:ma2], b[mi1:ma1, mi2:ma2]))
    end
end

"""
    compare_media(a_path, b_path) -> Float64

Score two PNG files (lower is better; `Inf` on size mismatch).
"""
function compare_media(a::AbstractString, b::AbstractString)
    return compare_images(PNGFiles.load(a), PNGFiles.load(b))
end

"""
    score_directory(recorded_dir, reference_dir; threshold = 0.05, out_dir = recorded_dir)

Score every PNG present in both directories (recursively, by relative path).
Writes `scores.tsv` (path → score), `missing_files.txt` (in reference, not
recorded) and `new_files.txt` (recorded, no reference) into `out_dir`.
Returns `(passed, total, rate, scores)` — the refpass metric.
"""
function score_directory(recorded_dir::AbstractString, reference_dir::AbstractString;
                         threshold::Float64 = 0.05, out_dir::AbstractString = recorded_dir)
    relpaths(dir) = sort!([relpath(joinpath(root, f), dir)
                           for (root, _, files) in walkdir(dir) for f in files
                           if endswith(f, ".png")])
    recorded = relpaths(recorded_dir)
    reference = relpaths(reference_dir)

    shared = intersect(recorded, reference)
    missing_files = setdiff(reference, recorded)
    new_files = setdiff(recorded, reference)

    scores = Dict{String,Float64}()
    for p in shared
        scores[p] = compare_media(joinpath(recorded_dir, p), joinpath(reference_dir, p))
    end

    open(joinpath(out_dir, "scores.tsv"), "w") do io
        for p in sort!(collect(keys(scores)))
            println(io, scores[p], '\t', p)
        end
    end
    write(joinpath(out_dir, "missing_files.txt"), join(missing_files, '\n'))
    write(joinpath(out_dir, "new_files.txt"), join(new_files, '\n'))

    passed = count(s -> s <= threshold, values(scores))
    total = length(scores)
    return (passed = passed, total = total,
            rate = total == 0 ? 0.0 : passed / total, scores = scores)
end

const REFIMAGES_TAG = "refimages-v0.24.0"  # matches the Makie 0.24.11 pin
refimages_url(tag::AbstractString = REFIMAGES_TAG) =
    "https://github.com/MakieOrg/Makie.jl/releases/download/$(tag)/reference_images.tar"

"""
    fetch_reference_images(; tag = REFIMAGES_TAG, dest = reftests/reference_images/<tag>)

Download and extract the pinned reference-image tarball (MIT release asset of
MakieOrg/Makie.jl). Cached: returns immediately if `dest` already exists.
The directory is gitignored — never commit reference images.
"""
function fetch_reference_images(; tag::AbstractString = REFIMAGES_TAG,
                                dest::AbstractString = joinpath(@__DIR__, "reference_images", tag))
    isdir(dest) && return dest
    tarball = Downloads.download(refimages_url(tag))
    Tar.extract(tarball, dest)
    rm(tarball; force = true)
    return dest
end

end # module

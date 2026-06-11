# Fixed-size geometry for the static core — Vec2/Vec3/Vec4, Mat4 (column-
# major), Rect2 — with exactly the operation surface the render/projection
# paths need (combined transform = viewport ∘ clip ∘ model; Mat4·Vec4).
#
# DECISION (C-005): this is a purpose-built NTuple-backed implementation, NOT
# vendored GeometryBasics. The alternative (GeometryBasics' StaticArrays
# types) was compiled through WasmTarget head-to-head — see the C-005 test
# and the plan's story log for the recorded outcome. API mirrors the subset
# of GeometryBasics the adapters use, so later swaps stay mechanical.

struct Vec2
    x::Float64
    y::Float64
end

struct Vec4
    x::Float64
    y::Float64
    z::Float64
    w::Float64
end

"4×4 matrix, column-major (matches GeometryBasics/Makie Mat4 layout)."
struct Mat4
    m::NTuple{16,Float64}
end

Base.getindex(A::Mat4, i::Integer, j::Integer) = A.m[(j - 1) * 4 + i]

const MAT4_I = Mat4((1.0, 0.0, 0.0, 0.0,
                     0.0, 1.0, 0.0, 0.0,
                     0.0, 0.0, 1.0, 0.0,
                     0.0, 0.0, 0.0, 1.0))

"Translation matrix (mirrors Makie.transformationmatrix(offset, scale))."
function mat4_translation_scale(tx::Float64, ty::Float64, tz::Float64,
                                sx::Float64, sy::Float64, sz::Float64)
    return Mat4((sx, 0.0, 0.0, 0.0,
                 0.0, sy, 0.0, 0.0,
                 0.0, 0.0, sz, 0.0,
                 tx, ty, tz, 1.0))
end

# WTGAP(9d411ad8ae24): `ntuple(f, 16)` with a closure stack-overflows the
# WasmTarget compiler — explicitly unrolled instead (matches what
# StaticArrays' @generated code produces, which DOES compile).
function mat4_mul(A::Mat4, B::Mat4)
    a = A.m
    b = B.m
    @inline col(j0) = (
        a[1] * b[j0 + 1] + a[5] * b[j0 + 2] + a[9] * b[j0 + 3] + a[13] * b[j0 + 4],
        a[2] * b[j0 + 1] + a[6] * b[j0 + 2] + a[10] * b[j0 + 3] + a[14] * b[j0 + 4],
        a[3] * b[j0 + 1] + a[7] * b[j0 + 2] + a[11] * b[j0 + 3] + a[15] * b[j0 + 4],
        a[4] * b[j0 + 1] + a[8] * b[j0 + 2] + a[12] * b[j0 + 3] + a[16] * b[j0 + 4],
    )
    c1 = col(0)
    c2 = col(4)
    c3 = col(8)
    c4 = col(12)
    return Mat4((c1[1], c1[2], c1[3], c1[4],
                 c2[1], c2[2], c2[3], c2[4],
                 c3[1], c3[2], c3[3], c3[4],
                 c4[1], c4[2], c4[3], c4[4]))
end

function mat4_vec4(A::Mat4, v::Vec4)
    m = A.m
    return Vec4(
        m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13] * v.w,
        m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14] * v.w,
        m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15] * v.w,
        m[4] * v.x + m[8] * v.y + m[12] * v.z + m[16] * v.w,
    )
end

"The Cairo/Canvas viewport matrix (translated from CairoMakie cairo_viewport_matrix): ndc → y-down device px."
function mat4_viewport(w::Float64, h::Float64)
    return mat4_translation_scale(0.5 * w, 0.5 * h, 0.0, 0.5 * w, -0.5 * h, 1.0)
end

"Project a 2D point through a combined clip-space transform to device px."
function project_px(T::Mat4, x::Float64, y::Float64)
    p = mat4_vec4(T, Vec4(x, y, 0.0, 1.0))
    return Vec2(p.x / p.w, p.y / p.w)
end

struct Rect2
    x::Float64
    y::Float64
    w::Float64
    h::Float64
end

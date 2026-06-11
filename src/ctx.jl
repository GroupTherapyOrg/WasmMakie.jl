# Ctx duality — the seam between wasm execution and host-side recording.
#
# The draw layer calls ops as `move_to(ctx, x, y)`. Two concrete ctx types:
#
#   WasmCtx      — forwards every op to its `canvas_*` stub; under WasmTarget
#                  those calls become canvas2d imports. This is the only ctx
#                  type that is ever compiled to wasm.
#   RecordingCtx — appends a typed `Command` to a vector; host-side only.
#                  Command streams are the differential oracle: the same
#                  program run host-side and wasm-side (glue instrumented to
#                  log calls) must produce equal streams.
#
# Value-returning ops (measure_text_buf_*, width, height, device_pixel_ratio)
# return deterministic stand-ins on RecordingCtx, computed from tracked state
# (font size, text-buffer length) and fixed metric ratios. Programs that
# branch on real browser metrics need the deterministic-metrics work (plan
# T-004) before their streams compare equal; everything else compares today.
#
# All op methods are generated from CANVAS_OPS — nothing here is hand-listed
# except the 9 stateful/value methods on RecordingCtx.

abstract type AbstractCtx end

struct WasmCtx <: AbstractCtx end

struct Command
    op::Symbol
    fargs::Vector{Float64}  # Float64 args, declaration order
    iargs::Vector{Int64}    # Int64 args, declaration order
end

Base.:(==)(a::Command, b::Command) =
    a.op === b.op && a.fargs == b.fargs && a.iargs == b.iargs

mutable struct RecordingCtx <: AbstractCtx
    commands::Vector{Command}
    # tracked state for deterministic value-op stand-ins
    buf_len::Int64
    font_size::Float64
    next_gradient_id::Int64  # mirrors the glue's sequential handle ids
    # fixed stand-in metrics (see T-004 for the path to real-metric parity)
    char_width_ratio::Float64
    ascent_ratio::Float64
    descent_ratio::Float64
    canvas_w::Float64
    canvas_h::Float64
    dpr::Float64
end

RecordingCtx(; canvas_w = 640.0, canvas_h = 480.0) =
    RecordingCtx(Command[], 0, 10.0, 0, 0.55, 0.8, 0.2, canvas_w, canvas_h, 1.0)

# Ops with hand-written RecordingCtx methods (stateful or value-returning).
const _SPECIAL_RECORDING_OPS = (
    :set_font, :text_buf_clear, :text_buf_push,
    :gradient_linear_new, :gradient_clear_all,
    :measure_text_buf_width, :measure_text_buf_ascent, :measure_text_buf_descent,
    :measure_text_buf_left, :measure_text_buf_right,
    :measure_text_buf_font_ascent, :measure_text_buf_font_descent,
    :width, :height, :device_pixel_ratio,
)

for op in CANVAS_OPS
    fname = op.name
    stub = Symbol(:canvas_, op.name)
    argnames = [first(p) for p in op.args]
    argexprs = [Expr(:(::), a, T) for (a, T) in op.args]
    fnames = [a for (a, T) in op.args if T === Float64]
    inames = [a for (a, T) in op.args if T === Int64]

    # WasmCtx: forward to the stub (becomes the wasm import call)
    @eval $fname(::WasmCtx, $(argexprs...)) = $stub($(argnames...))

    # RecordingCtx: record (special ops are hand-written below)
    if !(fname in _SPECIAL_RECORDING_OPS)
        @eval function $fname(ctx::RecordingCtx, $(argexprs...))
            push!(ctx.commands, Command($(QuoteNode(fname)), Float64[$(fnames...)], Int64[$(inames...)]))
            return Int64(0)
        end
    end
end

# ── stateful recording ops ──────────────────────────────────────────────
function set_font(ctx::RecordingCtx, fam::Int64, size::Float64, weight::Int64, italic::Int64)
    push!(ctx.commands, Command(:set_font, Float64[size], Int64[fam, weight, italic]))
    ctx.font_size = size
    return Int64(0)
end

function text_buf_clear(ctx::RecordingCtx)
    push!(ctx.commands, Command(:text_buf_clear, Float64[], Int64[]))
    ctx.buf_len = 0
    return Int64(0)
end

function text_buf_push(ctx::RecordingCtx, cp::Int64)
    push!(ctx.commands, Command(:text_buf_push, Float64[], Int64[cp]))
    ctx.buf_len += 1
    return Int64(0)
end

function gradient_linear_new(ctx::RecordingCtx, x0::Float64, y0::Float64, x1::Float64, y1::Float64)
    push!(ctx.commands, Command(:gradient_linear_new, Float64[x0, y0, x1, y1], Int64[]))
    id = ctx.next_gradient_id
    ctx.next_gradient_id += 1
    return id
end

function gradient_clear_all(ctx::RecordingCtx)
    push!(ctx.commands, Command(:gradient_clear_all, Float64[], Int64[]))
    ctx.next_gradient_id = 0
    return Int64(0)
end

# ── value-returning recording ops (deterministic stand-ins) ─────────────
function measure_text_buf_width(ctx::RecordingCtx)
    push!(ctx.commands, Command(:measure_text_buf_width, Float64[], Int64[]))
    return ctx.char_width_ratio * ctx.font_size * ctx.buf_len
end

function measure_text_buf_ascent(ctx::RecordingCtx)
    push!(ctx.commands, Command(:measure_text_buf_ascent, Float64[], Int64[]))
    return ctx.ascent_ratio * ctx.font_size
end

function measure_text_buf_descent(ctx::RecordingCtx)
    push!(ctx.commands, Command(:measure_text_buf_descent, Float64[], Int64[]))
    return ctx.descent_ratio * ctx.font_size
end

# ink bounds stand-ins: fixed 0.04·size side bearing (real values via the
# loaded fonts in browsers; bit-exact parity is the T-004 metric tables)
function measure_text_buf_left(ctx::RecordingCtx)
    push!(ctx.commands, Command(:measure_text_buf_left, Float64[], Int64[]))
    return 0.04 * ctx.font_size
end

function measure_text_buf_right(ctx::RecordingCtx)
    push!(ctx.commands, Command(:measure_text_buf_right, Float64[], Int64[]))
    return ctx.char_width_ratio * ctx.font_size * ctx.buf_len - 0.04 * ctx.font_size
end

# font-box stand-ins (fontBoundingBoxAscent/Descent): fixed 0.9/0.25·size
function measure_text_buf_font_ascent(ctx::RecordingCtx)
    push!(ctx.commands, Command(:measure_text_buf_font_ascent, Float64[], Int64[]))
    return 0.9 * ctx.font_size
end

function measure_text_buf_font_descent(ctx::RecordingCtx)
    push!(ctx.commands, Command(:measure_text_buf_font_descent, Float64[], Int64[]))
    return 0.25 * ctx.font_size
end

function width(ctx::RecordingCtx)
    push!(ctx.commands, Command(:width, Float64[], Int64[]))
    return ctx.canvas_w
end

function height(ctx::RecordingCtx)
    push!(ctx.commands, Command(:height, Float64[], Int64[]))
    return ctx.canvas_h
end

function device_pixel_ratio(ctx::RecordingCtx)
    push!(ctx.commands, Command(:device_pixel_ratio, Float64[], Int64[]))
    return ctx.dpr
end

# ── serialization (for assets/replay.js and the harness) ────────────────
const OP_TABLE = Dict{Symbol,CanvasOp}(op.name => op for op in CANVAS_OPS)

function _json_num(x::Float64)
    isfinite(x) || throw(ArgumentError("non-finite canvas arg: $x"))
    return string(x)
end

"""
    to_json(commands) -> String

Serialize a command stream as a JSON array of `{"op": name, "args": [...]}`
objects, args interleaved back into declaration order (the ops table defines
which positions are Int64 vs Float64). Consumed by `assets/replay.js`.
"""
function to_json(cmds::Vector{Command})
    parts = String[]
    for c in cmds
        op = OP_TABLE[c.op]
        vals = String[]
        fi, ii = 1, 1
        for (_, T) in op.args
            if T === Float64
                push!(vals, _json_num(c.fargs[fi])); fi += 1
            else
                push!(vals, string(c.iargs[ii])); ii += 1
            end
        end
        push!(parts, "{\"op\":\"$(c.op)\",\"args\":[$(join(vals, ","))]}")
    end
    return "[" * join(parts, ",") * "]"
end

to_json(ctx::RecordingCtx) = to_json(ctx.commands)

# The canvas ops table — the SINGLE SOURCE OF TRUTH for the Canvas2D surface.
#
# Every op declares: Julia stub signature, wasm signature (derived from the
# Julia types), and the JS implementation body. Three artifacts generate from
# this one table and may never be hand-maintained anywhere else:
#   1. the `canvas_*` Julia stub functions (wasm import targets, WasmPlot pattern)
#   2. `import_specs()` — metadata hosts use to register wasm imports
#   3. `js_glue()` — the canonical JS import-object factory
#
# Conventions:
#   - Fire-and-forget ops return Int64 (JS returns 0n); value ops return Float64.
#   - Int64 params cross to JS as BigInt; JS bodies convert with Number() and
#     compare against 0n for flags.
#   - Variable-length data crosses via buffer ops (text_buf_*, img_buf_*) so no
#     strings or arrays cross the import boundary; per-element pushes are the
#     v1 mechanism (bulk paths can come later via typed-array imports).
#   - Gradients use a handle model: integer ids into glue-side state.

struct CanvasOp
    name::Symbol
    args::Vector{Pair{Symbol,DataType}}
    ret::DataType
    js::String
end

const F = Float64
const I = Int64

const CANVAS_OPS = CanvasOp[
    # ── paths ────────────────────────────────────────────────────────────
    CanvasOp(:begin_path, [], I, "() => { ctx.beginPath(); return 0n; }"),
    CanvasOp(:close_path, [], I, "() => { ctx.closePath(); return 0n; }"),
    CanvasOp(:move_to, [:x=>F, :y=>F], I, "(x, y) => { ctx.moveTo(x, y); return 0n; }"),
    CanvasOp(:line_to, [:x=>F, :y=>F], I, "(x, y) => { ctx.lineTo(x, y); return 0n; }"),
    CanvasOp(:bezier_curve_to, [:c1x=>F, :c1y=>F, :c2x=>F, :c2y=>F, :x=>F, :y=>F], I,
        "(c1x, c1y, c2x, c2y, x, y) => { ctx.bezierCurveTo(c1x, c1y, c2x, c2y, x, y); return 0n; }"),
    CanvasOp(:quadratic_curve_to, [:cx=>F, :cy=>F, :x=>F, :y=>F], I,
        "(cx, cy, x, y) => { ctx.quadraticCurveTo(cx, cy, x, y); return 0n; }"),
    CanvasOp(:arc, [:x=>F, :y=>F, :r=>F, :sa=>F, :ea=>F, :ccw=>I], I,
        "(x, y, r, sa, ea, ccw) => { ctx.arc(x, y, r, sa, ea, ccw !== 0n); return 0n; }"),
    CanvasOp(:ellipse, [:x=>F, :y=>F, :rx=>F, :ry=>F, :rot=>F, :sa=>F, :ea=>F, :ccw=>I], I,
        "(x, y, rx, ry, rot, sa, ea, ccw) => { ctx.ellipse(x, y, rx, ry, rot, sa, ea, ccw !== 0n); return 0n; }"),
    CanvasOp(:rect, [:x=>F, :y=>F, :w=>F, :h=>F], I, "(x, y, w, h) => { ctx.rect(x, y, w, h); return 0n; }"),

    # ── drawing ──────────────────────────────────────────────────────────
    CanvasOp(:fill_nonzero, [], I, "() => { ctx.fill('nonzero'); return 0n; }"),
    CanvasOp(:fill_evenodd, [], I, "() => { ctx.fill('evenodd'); return 0n; }"),
    CanvasOp(:stroke, [], I, "() => { ctx.stroke(); return 0n; }"),
    CanvasOp(:fill_rect, [:x=>F, :y=>F, :w=>F, :h=>F], I, "(x, y, w, h) => { ctx.fillRect(x, y, w, h); return 0n; }"),
    CanvasOp(:stroke_rect, [:x=>F, :y=>F, :w=>F, :h=>F], I, "(x, y, w, h) => { ctx.strokeRect(x, y, w, h); return 0n; }"),
    CanvasOp(:clear_rect, [:x=>F, :y=>F, :w=>F, :h=>F], I, "(x, y, w, h) => { ctx.clearRect(x, y, w, h); return 0n; }"),
    CanvasOp(:clip_nonzero, [], I, "() => { ctx.clip('nonzero'); return 0n; }"),
    CanvasOp(:clip_evenodd, [], I, "() => { ctx.clip('evenodd'); return 0n; }"),

    # ── style ────────────────────────────────────────────────────────────
    CanvasOp(:set_fill_rgba, [:r=>F, :g=>F, :b=>F, :a=>F], I,
        "(r, g, b, a) => { ctx.fillStyle = 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')'; return 0n; }"),
    CanvasOp(:set_stroke_rgba, [:r=>F, :g=>F, :b=>F, :a=>F], I,
        "(r, g, b, a) => { ctx.strokeStyle = 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')'; return 0n; }"),
    CanvasOp(:set_line_width, [:w=>F], I, "(w) => { ctx.lineWidth = w; return 0n; }"),
    CanvasOp(:set_line_cap, [:k=>I], I,
        "(k) => { ctx.lineCap = ['butt', 'round', 'square'][Number(k)]; return 0n; }"),
    CanvasOp(:set_line_join, [:k=>I], I,
        "(k) => { ctx.lineJoin = ['miter', 'round', 'bevel'][Number(k)]; return 0n; }"),
    CanvasOp(:set_miter_limit, [:m=>F], I, "(m) => { ctx.miterLimit = m; return 0n; }"),
    CanvasOp(:set_global_alpha, [:a=>F], I, "(a) => { ctx.globalAlpha = a; return 0n; }"),
    CanvasOp(:set_line_dash4, [:d1=>F, :d2=>F, :d3=>F, :d4=>F, :n=>I], I,
        "(d1, d2, d3, d4, n) => { ctx.setLineDash([d1, d2, d3, d4].slice(0, Number(n))); return 0n; }"),
    CanvasOp(:set_line_dash_offset, [:o=>F], I, "(o) => { ctx.lineDashOffset = o; return 0n; }"),
    # buffered dash protocol for patterns longer than 4 (e.g. Makie :dashdotdot → 6)
    CanvasOp(:dash_buf_clear, [], I, "() => { S.dash = []; return 0n; }"),
    CanvasOp(:dash_buf_push, [:d=>F], I, "(d) => { S.dash.push(d); return 0n; }"),
    CanvasOp(:set_line_dash_buf, [], I, "() => { ctx.setLineDash(S.dash); return 0n; }"),

    # ── transforms ───────────────────────────────────────────────────────
    CanvasOp(:save, [], I, "() => { ctx.save(); return 0n; }"),
    CanvasOp(:restore, [], I, "() => { ctx.restore(); return 0n; }"),
    CanvasOp(:translate, [:x=>F, :y=>F], I, "(x, y) => { ctx.translate(x, y); return 0n; }"),
    CanvasOp(:scale_xy, [:x=>F, :y=>F], I, "(x, y) => { ctx.scale(x, y); return 0n; }"),
    CanvasOp(:rotate, [:a=>F], I, "(a) => { ctx.rotate(a); return 0n; }"),
    CanvasOp(:transform, [:a=>F, :b=>F, :c=>F, :d=>F, :e=>F, :f=>F], I,
        "(a, b, c, d, e, f) => { ctx.transform(a, b, c, d, e, f); return 0n; }"),
    CanvasOp(:set_transform, [:a=>F, :b=>F, :c=>F, :d=>F, :e=>F, :f=>F], I,
        "(a, b, c, d, e, f) => { ctx.setTransform(a, b, c, d, e, f); return 0n; }"),
    CanvasOp(:reset_transform, [], I, "() => { ctx.resetTransform(); return 0n; }"),

    # ── gradients (handle model) ─────────────────────────────────────────
    CanvasOp(:gradient_linear_new, [:x0=>F, :y0=>F, :x1=>F, :y1=>F], I,
        "(x0, y0, x1, y1) => { S.grads.push(ctx.createLinearGradient(x0, y0, x1, y1)); return BigInt(S.grads.length - 1); }"),
    CanvasOp(:gradient_add_stop, [:id=>I, :off=>F, :r=>F, :g=>F, :b=>F, :a=>F], I,
        "(id, off, r, g, b, a) => { S.grads[Number(id)].addColorStop(off, 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')'); return 0n; }"),
    CanvasOp(:set_fill_gradient, [:id=>I], I, "(id) => { ctx.fillStyle = S.grads[Number(id)]; return 0n; }"),
    CanvasOp(:set_stroke_gradient, [:id=>I], I, "(id) => { ctx.strokeStyle = S.grads[Number(id)]; return 0n; }"),
    CanvasOp(:gradient_clear_all, [], I, "() => { S.grads.length = 0; return 0n; }"),

    # ── text (buffered codepoint protocol — no strings cross the boundary) ─
    CanvasOp(:set_font, [:fam=>I, :size=>F, :weight=>I, :italic=>I], I,
        "(fam, size, weight, italic) => { S.font = { fam: Number(fam), size: size, weight: Number(weight), italic: Number(italic) }; setFont(); return 0n; }"),
    CanvasOp(:set_text_align, [:k=>I], I,
        "(k) => { ctx.textAlign = ['left', 'center', 'right'][Number(k)]; return 0n; }"),
    CanvasOp(:set_text_baseline, [:k=>I], I,
        "(k) => { ctx.textBaseline = ['alphabetic', 'top', 'middle', 'bottom'][Number(k)]; return 0n; }"),
    CanvasOp(:text_buf_clear, [], I, "() => { S.buf = ''; return 0n; }"),
    CanvasOp(:text_buf_push, [:cp=>I], I, "(cp) => { S.buf += String.fromCodePoint(Number(cp)); return 0n; }"),
    CanvasOp(:fill_text_buf, [:x=>F, :y=>F], I, "(x, y) => { ctx.fillText(S.buf, x, y); return 0n; }"),
    CanvasOp(:fill_text_char, [:cp=>I, :x=>F, :y=>F], I,
        "(cp, x, y) => { ctx.fillText(String.fromCodePoint(Number(cp)), x, y); return 0n; }"),
    CanvasOp(:measure_text_buf_width, [], F, "() => ctx.measureText(S.buf).width"),
    CanvasOp(:measure_text_buf_ascent, [], F,
        "() => { const m = ctx.measureText(S.buf); return m.actualBoundingBoxAscent ?? 0; }"),
    CanvasOp(:measure_text_buf_descent, [], F,
        "() => { const m = ctx.measureText(S.buf); return m.actualBoundingBoxDescent ?? 0; }"),
    CanvasOp(:measure_text_buf_left, [], F,
        "() => { const m = ctx.measureText(S.buf); return m.actualBoundingBoxLeft ?? 0; }"),
    CanvasOp(:measure_text_buf_right, [], F,
        "() => { const m = ctx.measureText(S.buf); return m.actualBoundingBoxRight ?? 0; }"),

    # ── images (buffered RGBA protocol) ──────────────────────────────────
    CanvasOp(:img_buf_new, [:w=>I, :h=>I], I,
        "(w, h) => { S.imgW = Number(w); S.imgH = Number(h); S.img = new Uint8ClampedArray(S.imgW * S.imgH * 4); S.imgI = 0; return 0n; }"),
    CanvasOp(:img_buf_push_rgba, [:r=>I, :g=>I, :b=>I, :a=>I], I,
        "(r, g, b, a) => { S.img[S.imgI++] = Number(r); S.img[S.imgI++] = Number(g); S.img[S.imgI++] = Number(b); S.img[S.imgI++] = Number(a); return 0n; }"),
    CanvasOp(:put_image_buf, [:x=>F, :y=>F], I,
        "(x, y) => { ctx.putImageData(new ImageData(S.img, S.imgW, S.imgH), x, y); return 0n; }"),
    CanvasOp(:draw_image_buf, [:x=>F, :y=>F, :w=>F, :h=>F], I,
        "(x, y, w, h) => { const oc = new OffscreenCanvas(S.imgW, S.imgH); oc.getContext('2d').putImageData(new ImageData(S.img, S.imgW, S.imgH), 0, 0); ctx.drawImage(oc, x, y, w, h); return 0n; }"),
    CanvasOp(:set_image_smoothing, [:on=>I], I,
        "(on) => { ctx.imageSmoothingEnabled = on !== 0n; return 0n; }"),

    # ── misc ─────────────────────────────────────────────────────────────
    CanvasOp(:set_global_composite, [:k=>I], I,
        "(k) => { ctx.globalCompositeOperation = ['source-over', 'lighter', 'multiply', 'copy'][Number(k)]; return 0n; }"),
    CanvasOp(:width, [], F, "() => ctx.canvas ? ctx.canvas.width : 0"),
    CanvasOp(:height, [], F, "() => ctx.canvas ? ctx.canvas.height : 0"),
    CanvasOp(:device_pixel_ratio, [], F,
        "() => (typeof devicePixelRatio !== 'undefined') ? devicePixelRatio : 1"),
]

# ── artifact 1: the canvas_* stub functions ─────────────────────────────
# @noinline + Base.donotdelete keeps the :invoke alive in optimized IR so the
# compiler's function registry can swap each call for a wasm import (the
# pattern WasmPlot validated). Native execution is a no-op returning zero —
# host-side rendering goes through RecordingCtx, never these stubs.
#
# Base.inferencebarrier on the return is LOAD-BEARING: without it, inference
# const-props the literal zero into callers, so compiled wasm would call the
# import but use the folded constant instead of the import's actual result
# (discovered in F-007: measure_text_buf_width returned 0.0 into the caller
# while the real measureText ran for nothing; gradient handle ids would all
# fold to 0 the same way).
for op in CANVAS_OPS
    fname = Symbol(:canvas_, op.name)
    argnames = [first(p) for p in op.args]
    argexprs = [Expr(:(::), a, T) for (a, T) in op.args]
    retval = op.ret === Float64 ? 0.0 : Int64(0)
    @eval @noinline function $fname($(argexprs...))
        Base.donotdelete($(argnames...))
        return Base.inferencebarrier($retval)::$(op.ret)
    end
    @eval export $fname
end

_wasm_type(::Type{Float64}) = :F64
_wasm_type(::Type{Int64}) = :I64

# ── artifact 2: import specs (host-facing metadata) ─────────────────────
"""
    import_specs() -> Vector{NamedTuple}

Metadata for every Canvas2D import, generated from the ops table. Hosts use
this to register wasm imports (module `"canvas2d"`) when compiling functions
that draw through WasmMakie. Fields per op: `name`, `mod`, `params`/`ret`
(wasm type symbols), `arg_types`/`return_type` (Julia types), `func` (the
stub function whose calls become the import).
"""
function import_specs()
    return [(
        name = String(op.name),
        mod = "canvas2d",
        params = Symbol[_wasm_type(T) for (_, T) in op.args],
        ret = _wasm_type(op.ret),
        arg_types = DataType[T for (_, T) in op.args],
        return_type = op.ret,
        func = getfield(@__MODULE__, Symbol(:canvas_, op.name)),
    ) for op in CANVAS_OPS]
end

# ── artifact 3: replay specs ────────────────────────────────────────────
"""
    js_specs() -> String

A JSON object mapping each op name to its wasm param kinds
(`{"move_to":["F64","F64"], "arc":[...,"I64"], ...}`), generated from the ops
table. `assets/replay.js` uses it to convert plain JSON numbers back into
wasm-shaped arguments (BigInt for I64) before calling the glue.
"""
function js_specs()
    entries = join(
        ["\"$(op.name)\":[$(join(["\"$(_wasm_type(T))\"" for (_, T) in op.args], ","))]"
         for op in CANVAS_OPS], ",")
    return "{" * entries * "}"
end

# ── artifact 4: the JS glue ─────────────────────────────────────────────
"""
    js_glue() -> String

The canonical JS import-object factory, generated from the ops table. Defines
`canvas2d_imports(target)` where `target` is a `<canvas>` element or a 2d
context; returns the object to pass as the `canvas2d` wasm import module.
Also defines `canvas2d_load_fonts(faces)` — an async FontFace loader hosts
await before drawing so `fill_text`/`measure_text` use the bundled Makie
fonts (T-001; faces shape = `font_faces_json()`). Hosts embed this string
verbatim — it is the only JS implementation of the ops table anywhere.
"""
function js_glue()
    entries = join(["    $(op.name): $(op.js)" for op in CANVAS_OPS], ",\n")
    return """
function canvas2d_imports(target) {
  const ctx = (target && target.getContext) ? target.getContext('2d') : target;
  const S = { grads: [], buf: '', dash: [], img: null, imgW: 0, imgH: 0, imgI: 0,
              fonts: ['"TeX Gyre Heros Makie", sans-serif', '"DejaVu Sans", sans-serif', 'monospace'],
              font: { fam: 0, size: 10, weight: 400, italic: 0 } };
  const setFont = () => { ctx.font = (S.font.italic ? 'italic ' : '') + S.font.weight + ' ' + S.font.size + 'px ' + S.fonts[S.font.fam]; };
  return {
$entries
  };
}
async function canvas2d_load_fonts(faces) {
  if (typeof document === 'undefined' || !document.fonts) return false;
  await Promise.all(faces.map(f =>
    new FontFace(f.family, 'url(' + f.url + ')',
                 { weight: String(f.weight), style: f.style })
      .load().then(face => { document.fonts.add(face); })));
  return true;
}
"""
end

# W-007 — record the M3 budgets on the Therapy-dashboard scenario (the
# 4-subplot all-types grid, wasm_corpus k13):
#
#   julia +1.12 --project=test reftests/run_budgets.jl
#
#   1. module size  — raw + gzip, before and after `wasm-opt -Oz` (the
#      shipping pipeline; hosts serve the optimized module gzipped)
#   2. compile time — cold (first WasmTarget compile in the session) + warm
#   3. redraw latency — node-side: instantiate once, re-invoke the figure
#      kernel (full stateless recompute, the islands model) with no-op
#      canvas imports; median of 200 calls. This is the wasm-compute cost
#      per interaction; canvas rasterization is the browser's own budget.
#
# The -Oz module must produce a command stream EQUAL to the host (checked
# here — optimization may never change drawing semantics).
#
# Budgets (fail = print BUDGET-MISS, exit 1):
#   size_oz_gzip ≤ 400 KB · compile_warm ≤ 30 s · redraw_median ≤ 16 ms (60 fps)
using WasmMakie
import CodecZlib

include(joinpath(@__DIR__, "wasm_compile.jl")); using .WasmCompile
include(joinpath(@__DIR__, "wasm_corpus.jl"))

const OUT = joinpath(@__DIR__, "budgets.tsv")

gzkb(b) = length(transcode(CodecZlib.GzipCompressor, b)) / 1024

# ── 1+2. size + compile time (cold = this first call in a fresh session) ──
t0 = time(); compile_with_canvas(Any[(WasmCorpus.k13_grid_2x2, (), "k")]); t_cold = time() - t0
t0 = time(); bytes = compile_with_canvas(Any[(WasmCorpus.k13_grid_2x2, (), "k")]); t_warm = time() - t0

dir = mktempdir()
wasm_path = joinpath(dir, "k.wasm"); write(wasm_path, bytes)
oz_path = joinpath(dir, "k_oz.wasm")
wasm_opt = Sys.which("wasm-opt")
oz_bytes = if wasm_opt === nothing
    @warn "wasm-opt not installed — recording unoptimized sizes only"
    bytes
else
    run(`$wasm_opt -Oz --enable-gc --enable-reference-types --enable-bulk-memory
         --enable-nontrapping-float-to-int --enable-exception-handling
         $wasm_path -o $oz_path`)
    read(oz_path)
end

# ── stream-equality proof for the optimized module ─────────────────────────
fig = WasmMakie.Figure(size = (400.0, 300.0))
WasmMakie.lines!(WasmMakie.Axis(fig[1, 1]),
                 [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0], [0.1, 0.7, 0.4, 0.9, 0.3, 0.8, 0.5])
WasmMakie.scatter!(WasmMakie.Axis(fig[1, 2]),
                   [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0], [0.9, 0.2, 0.6, 0.1, 0.7, 0.3, 0.6])
WasmMakie.barplot!(WasmMakie.Axis(fig[2, 1]), [1.0, 2.0, 3.0], [1.0, 2.0, 1.5])
WasmMakie.lines!(WasmMakie.Axis(fig[2, 2]),
                 [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0], [0.9, 0.2, 0.6, 0.1, 0.7, 0.3, 0.6];
                 color = :green)
r = WasmMakie.RecordingCtx(); WasmMakie.render!(fig, r)
glue_path = joinpath(dir, "glue.js"); write(glue_path, WasmMakie.js_glue())
checker = joinpath(dirname(@__DIR__), "test", "wasm_stream_check.js")
check_path = wasm_opt === nothing ? wasm_path : oz_path
wasm_json = strip(read(`node $checker $check_path $glue_path k`, String))
norm(j) = strip(read(`node -e "console.log(JSON.stringify(JSON.parse(process.argv[1])))" $j`, String))
stream_equal = norm(WasmMakie.to_json(r)) == norm(wasm_json)
stream_equal || (println("BUDGET-MISS: -Oz module stream != host stream"); exit(1))

# ── 3. redraw latency in node (optimized module, no-op imports) ────────────
bench_js = joinpath(dir, "bench.js")
write(bench_js, """
const fs = require('fs');
WebAssembly.instantiate(fs.readFileSync(process.argv[2]),
    {canvas2d: new Proxy({}, {get: () => () => 0n}), Math: {pow: Math.pow}}).then(m => {
  const k = m.instance.exports.k;
  for (let i = 0; i < 20; i++) k();                 // warmup/JIT
  const times = [];
  for (let i = 0; i < 200; i++) {
    const t0 = process.hrtime.bigint();
    k();
    times.push(Number(process.hrtime.bigint() - t0) / 1e6);
  }
  times.sort((a, b) => a - b);
  console.log(JSON.stringify({
    median: times[100], p95: times[190], min: times[0], max: times[199]
  }));
});
""")
lat = read(`node $bench_js $check_path`, String)
m = match(r"\"median\":([\d.]+),\"p95\":([\d.]+),\"min\":([\d.]+),\"max\":([\d.]+)", lat)
median_ms = parse(Float64, m[1]); p95_ms = parse(Float64, m[2])
min_ms = parse(Float64, m[3]); max_ms = parse(Float64, m[4])

# ── record + gate ──────────────────────────────────────────────────────────
rows = [
    ("module_size_raw_kb", round(length(bytes) / 1024, digits = 1), "—"),
    ("module_size_gzip_kb", round(gzkb(bytes), digits = 1), "—"),
    ("module_size_oz_raw_kb", round(length(oz_bytes) / 1024, digits = 1), "—"),
    ("module_size_oz_gzip_kb", round(gzkb(oz_bytes), digits = 1), "≤ 400"),
    ("oz_stream_equal", stream_equal, "must hold"),
    ("compile_cold_s", round(t_cold, digits = 1), "—"),
    ("compile_warm_s", round(t_warm, digits = 1), "≤ 30"),
    ("redraw_median_ms", round(median_ms, digits = 3), "≤ 16 (60 fps)"),
    ("redraw_p95_ms", round(p95_ms, digits = 3), "—"),
    ("redraw_min_ms", round(min_ms, digits = 3), "—"),
    ("redraw_max_ms", round(max_ms, digits = 3), "—"),
]
open(OUT, "w") do io
    println(io, "# metric\tvalue\tbudget   (scene: 4-subplot all-types grid, 400×300; oz = wasm-opt -Oz)")
    for (k, v, b) in rows
        println(io, k, '\t', v, '\t', b)
    end
end
for (k, v, b) in rows
    println(rpad(k, 24), lpad(string(v), 10), "   budget ", b)
end

misses = String[]
gzkb(oz_bytes) <= 400 || push!(misses, "size_oz_gzip $(round(gzkb(oz_bytes), digits=1))KB > 400KB")
t_warm <= 30 || push!(misses, "compile_warm $(round(t_warm, digits=1))s > 30s")
median_ms <= 16 || push!(misses, "redraw_median $(round(median_ms, digits=3))ms > 16ms")
if isempty(misses)
    println("BUDGETS: all green")
else
    println("BUDGET-MISS: ", join(misses, " · "))
    exit(1)
end

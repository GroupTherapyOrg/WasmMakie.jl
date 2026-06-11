# W-006 stage 1 — compile every corpus kernel to wasm and render it on a real
# canvas in headless Chromium. PNGs land in reftests/recorded/wasm_corpus/.
#
#   julia +1.12 --project=test reftests/run_wasm_corpus_stage1.jl
#
# Stage 2 (run_wasm_corpus_stage2.jl, CanvasMakie env) scores these against
# real-Makie renders of the same scenes → the wasm_refpass metric.
using WasmMakie

include(joinpath(@__DIR__, "wasm_compile.jl")); using .WasmCompile
include(joinpath(@__DIR__, "harness.jl")); using .Harness
include(joinpath(@__DIR__, "wasm_corpus.jl"))

const W = 400
const H = 300

outdir = joinpath(@__DIR__, "recorded", "wasm_corpus")
rm(outdir; force = true, recursive = true)
mkpath(outdir)

failures = String[]
for (slug, kernel) in WasmCorpus.KERNELS
    t0 = time()
    bytes = try
        compile_with_canvas(Any[(kernel, (), "k")])
    catch e
        println(rpad(slug, 26), " COMPILE-FAIL ", typeof(e))
        push!(failures, slug * " (compile)")
        continue
    end
    res = try
        render_wasm(bytes, "k"; width = W, height = H)
    catch e
        println(rpad(slug, 26), " RENDER-FAIL ", first(string(e), 120))
        push!(failures, slug * " (render)")
        continue
    end
    if res === nothing
        println(rpad(slug, 26), " SKIP (playwright unavailable)")
        push!(failures, slug * " (no playwright)")
        continue
    end
    write(joinpath(outdir, slug * ".png"), res.png)
    println(rpad(slug, 26), " ok  ", length(bytes), " bytes wasm  ",
            round(time() - t0, digits = 1), "s")
end

if isempty(failures)
    println("STAGE1: all $(length(WasmCorpus.KERNELS)) scenes rendered")
else
    println("STAGE1: $(length(failures)) failures: ", join(failures, ", "))
end

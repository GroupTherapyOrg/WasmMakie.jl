# C-002: optimize_ticks parity vs PlotUtils (subprocess oracle).
#
# Included by runtests.jl — OR run standalone (CI does):
#
#     julia --project=test test/c002_parity.jl
#
# then set WASMMAKIE_SKIP_C002=1 for the main suite run. Why standalone on
# CI: the parent-side subprocess IO trips a Julia 1.12 GC segfault
# (jl_gc_small_alloc during readlines) that depends on accumulated heap/
# precompile state — deterministic on the Linux runners, flaky-once locally.
# A fresh process never accumulates the triggering state. The oracle itself
# ALSO spawns a subprocess: co-inferring our vendored copy and PlotUtils'
# original in one session segfaults the compiler (inference recursion).

if !@isdefined(WasmMakie)
    using WasmMakie
    using Test
end

@testset "optimize_ticks parity vs PlotUtils (C-002, subprocess oracle)" begin
    cases = [
        "(0.0, 10.0)", "(0.0, 1.0)", "(-5.0, 5.0)", "(0.001, 0.0023)",
        "(-1.0e6, 1.0e6)", "(2.5, 7.5)", "(0.0, 100.0)", "(-0.1, 0.7)",
        "(1234.5, 1236.7)", "(-273.15, 0.0)", "(0.0, 1.0e-9)",
        "(0.0, 10.0; extend_ticks=true)", "(-3.0, 17.0; k_max=4)",
        "(-3.0, 17.0; k_ideal=8, k_max=12)", "(-3.0, 17.0; strict_span=false)",
        "(0.0, 4.0; scale=:log10)", "(1.0, 9.0; scale=:log2)",
    ]
    script = "import PlotUtils\n" *
        join(["println(repr(PlotUtils.optimize_ticks$(c)))" for c in cases], "\n")
    proj = dirname(Base.active_project())
    # Base.julia_cmd() = the RUNNING julia — portable to CI (no juliaup there)
    jlcmd = Base.julia_cmd()
    # the oracle writes to a FILE read after exit: readlines on a live
    # process pipe segfaults Julia 1.12's GC (jl_gc_small_alloc during
    # StringVector growth) depending on heap state — deterministically on
    # the Linux CI runners and in this standalone file locally
    # --check-bounds=auto (last flag wins over whatever julia_cmd inherited):
    # under Pkg.test, julia_cmd carries --check-bounds=yes, which exposes a
    # latent @inbounds OOB in PlotUtils' own extend_ticks path (S-fill loop,
    # ticks.jl:265 in 1.4.3/1.4.4) and kills the oracle. The oracle must
    # measure PlotUtils as users run it — default bounds elision.
    oracle = mktempdir() do dir
        out = joinpath(dir, "oracle.txt")
        run(pipeline(`$jlcmd --check-bounds=auto --project=$proj --startup-file=no -e $script`; stdout=out))
        readlines(out)
    end
    @test length(oracle) == length(cases)
    # VALUE comparison, not repr strings: Ryu float `show` of the result
    # tuples trips the same 1.12 GC segfault (jl_gc_small_alloc under
    # ijl_alloc_string) — the oracle's printed literals parse back exactly,
    # and == on Float64s is the same bit-exactness the strings encoded.
    # GC stays off through the loop (tiny allocations) as belt-and-braces.
    GC.enable(false)
    try
        for (c, expected) in zip(cases, oracle)
            ours = eval(Meta.parse("WasmMakie.optimize_ticks$(c)"))
            expv = eval(Meta.parse(expected))
            @test ours == expv
        end
    finally
        GC.enable(true)
    end
end

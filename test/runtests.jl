using Test
using WasmMakie
import WasmTarget
import Base64 as _B64check

@testset "ops table (F-002)" begin
    ops = WasmMakie.CANVAS_OPS
    @test length(ops) == 65
    @test allunique([op.name for op in ops])
    # Only Float64/Int64 cross the import boundary
    for op in ops
        @test op.ret in (Float64, Int64)
        for (_, T) in op.args
            @test T in (Float64, Int64)
        end
    end

    # Stubs: generated, exported, callable, correct native return values
    @test WasmMakie.canvas_begin_path() === Int64(0)
    @test WasmMakie.canvas_move_to(1.0, 2.0) === Int64(0)
    @test WasmMakie.canvas_arc(0.0, 0.0, 1.0, 0.0, 6.28, Int64(0)) === Int64(0)
    @test WasmMakie.canvas_set_line_dash4(6.0, 4.0, 0.0, 0.0, Int64(2)) === Int64(0)
    @test WasmMakie.canvas_gradient_linear_new(0.0, 0.0, 1.0, 1.0) === Int64(0)
    @test WasmMakie.canvas_measure_text_buf_width() === 0.0
    @test WasmMakie.canvas_device_pixel_ratio() === 0.0
    for op in ops  # every op has a generated stub with matching arity
        f = getfield(WasmMakie, Symbol(:canvas_, op.name))
        @test length(methods(f)) == 1
        @test only(methods(f)).nargs == length(op.args) + 1
    end

    # import_specs: generated from the table, wasm types mapped correctly
    specs = import_specs()
    @test length(specs) == length(ops)
    mv = specs[findfirst(s -> s.name == "move_to", specs)]
    @test mv.mod == "canvas2d" && mv.params == [:F64, :F64] && mv.ret == :I64
    @test mv.func === WasmMakie.canvas_move_to
    ar = specs[findfirst(s -> s.name == "arc", specs)]
    @test ar.params == [:F64, :F64, :F64, :F64, :F64, :I64]
    mw = specs[findfirst(s -> s.name == "measure_text_buf_width", specs)]
    @test mw.ret == :F64 && isempty(mw.params)

    # js_glue: every op present, structurally sound
    glue = js_glue()
    @test occursin("function canvas2d_imports(target)", glue)
    for op in ops
        @test occursin("$(op.name):", glue)
    end
    @test count(==('{'), glue) == count(==('}'), glue)
end

@testset "js glue executes in node (F-002)" begin
    dir = mktempdir()
    glue_path = joinpath(dir, "glue.js")
    write(glue_path, js_glue())
    specs_json = "[" * join(
        ["""{"name":"$(s.name)","params":[$(join(["\"$p\"" for p in s.params], ","))],"ret":"$(s.ret)"}"""
         for s in import_specs()], ",") * "]"
    specs_path = joinpath(dir, "specs.json")
    write(specs_path, specs_json)
    checker = joinpath(@__DIR__, "js_glue_check.js")
    out = read(`node $checker $glue_path $specs_path`, String)
    @test occursin("JS GLUE OK: 65 ops", out)
end

@testset "ctx duality (F-003)" begin
    # Every op has methods for both ctx types
    for op in WasmMakie.CANVAS_OPS
        f = getfield(WasmMakie, op.name)
        sig_w = Tuple{WasmCtx, [T for (_, T) in op.args]...}
        sig_r = Tuple{RecordingCtx, [T for (_, T) in op.args]...}
        @test hasmethod(f, sig_w)
        @test hasmethod(f, sig_r)
    end

    # WasmCtx forwards to stubs (native no-ops with stub return values)
    w = WasmCtx()
    @test WasmMakie.move_to(w, 1.0, 2.0) === Int64(0)
    @test WasmMakie.measure_text_buf_width(w) === 0.0

    # A draw program, written once, runs against either ctx
    function program(ctx)
        WasmMakie.begin_path(ctx)
        WasmMakie.move_to(ctx, 1.0, 2.0)
        WasmMakie.line_to(ctx, 3.0, 4.5)
        WasmMakie.set_line_dash4(ctx, 6.0, 4.0, 0.0, 0.0, Int64(2))
        WasmMakie.stroke(ctx)
        return nothing
    end
    program(w)  # compiles & runs against WasmCtx

    r1 = RecordingCtx(); program(r1)
    @test length(r1.commands) == 5
    @test r1.commands[1] == Command(:begin_path, Float64[], Int64[])
    @test r1.commands[2] == Command(:move_to, [1.0, 2.0], Int64[])
    @test r1.commands[4] == Command(:set_line_dash4, [6.0, 4.0, 0.0, 0.0], Int64[2])

    # Command-stream equality: same program ⇒ equal; different ⇒ not
    r2 = RecordingCtx(); program(r2)
    @test r1.commands == r2.commands
    WasmMakie.line_to(r2, 9.0, 9.0)
    @test r1.commands != r2.commands

    # Int64 args preserved exactly (no float round-trip)
    r3 = RecordingCtx()
    big = Int64(2)^60 + 1
    WasmMakie.text_buf_push(r3, big)
    @test r3.commands[1].iargs == [big]

    # Deterministic value stand-ins track font + buffer state
    r4 = RecordingCtx()
    WasmMakie.set_font(r4, Int64(0), 12.0, Int64(400), Int64(0))
    WasmMakie.text_buf_clear(r4)
    WasmMakie.text_buf_push(r4, Int64(72))
    WasmMakie.text_buf_push(r4, Int64(105))
    @test WasmMakie.measure_text_buf_width(r4) == 0.55 * 12.0 * 2
    @test WasmMakie.measure_text_buf_ascent(r4) == 0.8 * 12.0
    @test WasmMakie.width(r4) == 640.0 && WasmMakie.height(r4) == 480.0
    @test WasmMakie.device_pixel_ratio(r4) == 1.0
    # value ops are themselves part of the recorded stream
    @test r4.commands[end].op === :device_pixel_ratio

    # JSON serialization: exact shape, declaration-order interleaving
    r5 = RecordingCtx()
    WasmMakie.move_to(r5, 1.0, 2.5)
    WasmMakie.arc(r5, 0.0, 0.0, 5.0, 0.0, 3.14, Int64(1))
    json = to_json(r5)
    @test json == "[{\"op\":\"move_to\",\"args\":[1.0,2.5]}," *
                  "{\"op\":\"arc\",\"args\":[0.0,0.0,5.0,0.0,3.14,1]}]"
    @test_throws ArgumentError to_json([Command(:move_to, [NaN, 0.0], Int64[])])

    # JSON is parseable (node is the consumer)
    parsed = read(`node -e "const a=JSON.parse(process.argv[1]);console.log(a.length)" $json`, String)
    @test strip(parsed) == "2"
end

@testset "replay round-trip (F-004)" begin
    # js_specs: generated, complete, JSON-parseable
    specs = WasmMakie.js_specs()
    @test occursin("\"arc\":[\"F64\",\"F64\",\"F64\",\"F64\",\"F64\",\"I64\"]", specs)
    @test occursin("\"begin_path\":[]", specs)
    nops = read(`node -e "console.log(Object.keys(JSON.parse(process.argv[1])).length)" $specs`, String)
    @test strip(nops) == "65"

    # Record a program exercising every conversion class, then replay it
    # through the REAL glue in node and assert the resulting canvas calls.
    r = RecordingCtx()
    WasmMakie.begin_path(r)
    WasmMakie.move_to(r, 1.0, 2.0)
    WasmMakie.arc(r, 0.0, 0.0, 5.0, 0.0, 3.14, Int64(1))
    WasmMakie.set_line_dash4(r, 6.0, 4.0, 0.0, 0.0, Int64(2))
    WasmMakie.set_line_cap(r, Int64(1))
    WasmMakie.set_font(r, Int64(0), 12.0, Int64(400), Int64(0))
    WasmMakie.text_buf_clear(r)
    WasmMakie.text_buf_push(r, Int64(72))   # 'H'
    WasmMakie.text_buf_push(r, Int64(105))  # 'i'
    WasmMakie.fill_text_buf(r, 10.0, 20.0)
    WasmMakie.img_buf_new(r, Int64(2), Int64(1))
    WasmMakie.img_buf_push_rgba(r, Int64(10), Int64(20), Int64(30), Int64(255))
    WasmMakie.img_buf_push_rgba(r, Int64(40), Int64(50), Int64(60), Int64(255))
    WasmMakie.put_image_buf(r, 0.0, 0.0)
    gid = WasmMakie.gradient_linear_new(r, 0.0, 0.0, 100.0, 0.0)
    @test gid === Int64(0)
    @test WasmMakie.gradient_linear_new(RecordingCtx(), 0.0, 0.0, 1.0, 1.0) === Int64(0)
    WasmMakie.gradient_add_stop(r, gid, 0.0, 255.0, 0.0, 0.0, 1.0)
    WasmMakie.set_fill_gradient(r, gid)
    WasmMakie.stroke(r)
    @test length(r.commands) == 18
    # sequential handle ids mirror the glue
    r9 = RecordingCtx()
    @test WasmMakie.gradient_linear_new(r9, 0.0, 0.0, 1.0, 0.0) === Int64(0)
    @test WasmMakie.gradient_linear_new(r9, 0.0, 0.0, 2.0, 0.0) === Int64(1)
    WasmMakie.gradient_clear_all(r9)
    @test WasmMakie.gradient_linear_new(r9, 0.0, 0.0, 3.0, 0.0) === Int64(0)

    dir = mktempdir()
    glue_path = joinpath(dir, "glue.js");     write(glue_path, js_glue())
    specs_path = joinpath(dir, "specs.json"); write(specs_path, specs)
    cmds_path = joinpath(dir, "commands.json"); write(cmds_path, to_json(r))
    replay_path = joinpath(dirname(@__DIR__), "assets", "replay.js")
    checker = joinpath(@__DIR__, "replay_check.js")
    out = read(`node $checker $glue_path $replay_path $specs_path $cmds_path`, String)
    @test occursin("REPLAY OK: 18 commands round-tripped", out)
end

include(joinpath(dirname(@__DIR__), "reftests", "harness.jl"))
using .Harness

include(joinpath(dirname(@__DIR__), "reftests", "scorer.jl"))
using .RefScorer
using ColorTypes, FixedPointNumbers
import PNGFiles

@testset "reference scorer (F-006)" begin
    white(h, w) = fill(RGBA{N0f8}(1, 1, 1, 1), h, w)

    # identical → 0
    @test compare_images(white(60, 60), white(60, 60)) == 0.0

    # size mismatch → Inf
    @test compare_images(white(60, 60), white(60, 90)) == Inf

    # upstream tiling: ceil(N/30) BOUNDARIES, so 60×60 = one 60×60 tile.
    # A black 30×30 quadrant in white → tile mean = √3·(900/3600) = √3/4
    b = white(60, 60)
    b[1:30, 1:30] .= RGBA{N0f8}(0, 0, 0, 1)
    @test compare_images(white(60, 60), b) ≈ sqrt(3) / 4 atol = 1e-3

    # localized (max-tile) sensitivity: 90×90 → boundaries [0,45,90] → four
    # 45×45 tiles. ONE black pixel scores √3/2025 (its tile's mean), NOT the
    # global mean √3/8100
    c = white(90, 90)
    c[5, 5] = RGBA{N0f8}(0, 0, 0, 1)
    @test compare_images(white(90, 90), c) ≈ sqrt(3) / 2025 atol = 1e-7
    @test compare_images(white(90, 90), c) > sqrt(3) / 8100

    # file path round-trips through PNG encode/decode
    dir = mktempdir()
    PNGFiles.save(joinpath(dir, "a.png"), white(60, 60))
    PNGFiles.save(joinpath(dir, "b.png"), b)
    @test compare_media(joinpath(dir, "a.png"), joinpath(dir, "b.png")) ≈ sqrt(3) / 4 atol = 1e-3

    # score_directory: 1 pass + 1 fail + 1 missing + 1 new → rate 0.5
    rec = mktempdir(); ref = mktempdir()
    PNGFiles.save(joinpath(rec, "same.png"), white(60, 60))
    PNGFiles.save(joinpath(ref, "same.png"), white(60, 60))
    PNGFiles.save(joinpath(rec, "diff.png"), white(60, 60))
    PNGFiles.save(joinpath(ref, "diff.png"), b)
    PNGFiles.save(joinpath(ref, "only_ref.png"), white(30, 30))
    PNGFiles.save(joinpath(rec, "only_rec.png"), white(30, 30))
    result = score_directory(rec, ref)
    @test result.total == 2 && result.passed == 1 && result.rate == 0.5
    @test result.scores["same.png"] == 0.0
    @test result.scores["diff.png"] > 0.05
    @test occursin("same.png", read(joinpath(rec, "scores.tsv"), String))
    @test strip(read(joinpath(rec, "missing_files.txt"), String)) == "only_ref.png"
    @test strip(read(joinpath(rec, "new_files.txt"), String)) == "only_rec.png"

    # the pinned reference tarball is fetchable (HEAD only — no download)
    code = strip(read(`curl -sIL -o /dev/null -w "%{http_code}" $(RefScorer.refimages_url())`, String))
    @test code == "200"
end

@testset "headless render harness (F-005)" begin
    # red rect program → real Chromium pixels
    r = RecordingCtx()
    WasmMakie.set_fill_rgba(r, 255.0, 0.0, 0.0, 1.0)
    WasmMakie.fill_rect(r, 10.0, 10.0, 100.0, 50.0)
    res = render_commands(to_json(r); width = 200, height = 100,
                          probes = [(12, 12), (5, 5), (150, 80)])
    if res === nothing
        @test_skip "playwright unavailable"
    else
        @test res.png[1:8] == UInt8[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        @test png_dims(res.png) == (200, 100)
        @test res.pixels[(12, 12)] == (255, 0, 0, 255)   # inside the rect
        @test res.pixels[(5, 5)] == (0, 0, 0, 0)         # outside: transparent
        @test res.pixels[(150, 80)] == (0, 0, 0, 0)

        # stroked thick line: midpoint is opaque black
        r2 = RecordingCtx()
        WasmMakie.begin_path(r2)
        WasmMakie.set_line_width(r2, 10.0)
        WasmMakie.move_to(r2, 0.0, 50.0)
        WasmMakie.line_to(r2, 200.0, 50.0)
        WasmMakie.stroke(r2)
        res2 = render_commands(to_json(r2); width = 200, height = 100, probes = [(100, 50)])
        @test res2.pixels[(100, 50)] == (0, 0, 0, 255)

        # page errors propagate with the JS message
        bad = "[{\"op\":\"begin_path\",\"args\":[1.0]}]"  # arity mismatch
        @test_throws Harness.PageError render_commands(bad)
    end
end

include(joinpath(dirname(@__DIR__), "reftests", "wasm_compile.jl"))
using .WasmCompile

# F-007 probe: exercises the two NEW import patterns — a value-returning f64
# import (measure_text_buf_width) whose result is both used for drawing and
# returned, and the buffered-byte image path.
function f007_probe()
    canvas_set_fill_rgba(255.0, 0.0, 0.0, 1.0)
    canvas_fill_rect(10.0, 10.0, 100.0, 50.0)
    canvas_set_font(Int64(0), 12.0, Int64(400), Int64(0))
    canvas_text_buf_clear()
    canvas_text_buf_push(Int64(72))   # 'H'
    canvas_text_buf_push(Int64(105))  # 'i'
    w = canvas_measure_text_buf_width()
    canvas_fill_text_buf(10.0, 80.0)
    canvas_fill_rect(0.0, 90.0, w, 5.0)
    canvas_img_buf_new(Int64(2), Int64(1))
    canvas_img_buf_push_rgba(Int64(0), Int64(255), Int64(0), Int64(255))
    canvas_img_buf_push_rgba(Int64(0), Int64(0), Int64(255), Int64(255))
    canvas_put_image_buf(150.0, 10.0)
    return w
end

@testset "WasmTarget e2e import proof (F-007)" begin
    bytes = compile_with_canvas(Any[(f007_probe, (), "f007_probe")])
    @test bytes isa Vector{UInt8}
    @test length(bytes) > 8
    @test bytes[1:4] == UInt8[0x00, 0x61, 0x73, 0x6D]  # \0asm

    # node: value-returning import + byte crossing, against a logging ctx
    dir = mktempdir()
    wasm_path = joinpath(dir, "probe.wasm"); write(wasm_path, bytes)
    glue_path = joinpath(dir, "glue.js");    write(glue_path, js_glue())
    checker = joinpath(@__DIR__, "wasm_e2e_check.js")
    out = read(`node $checker $wasm_path $glue_path f007_probe`, String)
    @test occursin("WASM E2E OK", out)
    @test occursin("result=42", out)

    # browser: the same module against a REAL canvas — pixels prove it
    res = render_wasm(bytes, "f007_probe"; width = 200, height = 100,
                      probes = [(12, 12), (150, 10), (151, 10), (2, 92), (199, 99)])
    if res === nothing
        @test_skip "playwright unavailable"
    else
        @test res.pixels[(12, 12)] == (255, 0, 0, 255)   # red rect
        @test res.pixels[(150, 10)] == (0, 255, 0, 255)  # image px 1: green
        @test res.pixels[(151, 10)] == (0, 0, 255, 255)  # image px 2: blue
        # the rect drawn with the REAL measured text width: its left edge is
        # opaque red (measureText('Hi') at 12px is comfortably > 2px wide)
        @test res.pixels[(2, 92)] == (255, 0, 0, 255)
        @test res.pixels[(199, 99)] == (0, 0, 0, 0)      # untouched corner
    end
end

@testset "static core: Figure/Axis/theme (C-001)" begin
    fig = Figure()
    @test fig.width == 600.0 && fig.height == 450.0
    @test fig.backgroundcolor == (1.0, 1.0, 1.0, 1.0)
    @test fig.padding == 16.0
    @test fig.rowgap == 18.0 && fig.colgap == 18.0
    @test isempty(fig.axes)

    fig2 = Figure(size = (800, 300), figure_padding = 8)
    @test fig2.width == 800.0 && fig2.height == 300.0
    @test fig2.padding == 8.0

    gp = fig[2, 3]
    @test gp isa GridPosition
    @test gp.row == 2 && gp.col == 3

    ax = Axis(fig[1, 1]; title = "T", xlabel = "x", ylabel = "y")
    @test length(fig.axes) == 1 && fig.axes[1] === ax
    @test ax.row == 1 && ax.col == 1
    @test ax.title == "T" && ax.xlabel == "x" && ax.ylabel == "y"
    @test isnan(ax.xmin) && isnan(ax.ymax)        # automatic limits
    @test ax.titlesize == 14.0 && ax.xlabelsize == 14.0  # titlesize @inherit(:fontsize)

    Axis(fig[2, 2])
    @test WasmMakie.grid_extents(fig) == (2, 2)

    # Wong palette: exact Makie values, mod-7 cycle
    @test cycle_color(1) == (0.0, 114 / 255, 178 / 255, 1.0)
    @test cycle_color(7) == (240 / 255, 228 / 255, 66 / 255, 1.0)
    @test cycle_color(8) == cycle_color(1)

    @test WasmMakie.THEME_FONTSIZE == 14.0
    @test WasmMakie.THEME_LINEWIDTH == 1.5
    @test WasmMakie.THEME_MARKERSIZE == 9.0
end

@testset "optimize_ticks parity vs PlotUtils (C-002, subprocess oracle)" begin
    # The oracle runs in its OWN process: co-inferring our vendored copy and
    # PlotUtils' original in one Julia 1.12 session segfaults the compiler
    # (inference recursion — reproduced minimally with just these two pkgs).
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
    oracle = readlines(`$jlcmd --project=$proj --startup-file=no -e $script`)
    @test length(oracle) == length(cases)
    for (c, expected) in zip(cases, oracle)
        ours = eval(Meta.parse("WasmMakie.optimize_ticks$(c)"))
        @test repr(ours) == expected
    end
end

@testset "tick label formatting (C-003) — Makie oracle hardcoded" begin
    # oracle: Makie.format_ticks_plain outputs captured live from 0.24.11
    F = WasmMakie.format_ticks_plain
    @test F([0.0, 5.0, 10.0]) == ["0", "5", "10"]
    @test F([0.0, 0.25, 0.5, 0.75, 1.0]) == ["0.00", "0.25", "0.50", "0.75", "1.00"]
    @test F([-5.0, 0.0, 5.0]) == ["−5", "0", "5"]
    @test F([0.001, 0.0015, 0.002]) == ["0.0010", "0.0015", "0.0020"]
    @test F([1234.5, 1235.0, 1236.7]) == ["1234.5", "1235.0", "1236.7"]
    @test F([-273.15, -100.0, 0.0]) == ["−273.15", "−100.00", "0.00"]
    @test F([1.0e6, 2.0e6]) == ["1000000", "2000000"]
    @test F([0.0, 1.0e-9, 2.0e-9]) ==
          ["0.000000000", "0.000000001", "0.000000002"]

    # auto: plain ranges → plain TickLabels
    auto1 = WasmMakie.format_ticks_auto([0.0, 5.0, 10.0])
    @test auto1 == [WasmMakie.TickLabel("0", ""), WasmMakie.TickLabel("5", ""),
                    WasmMakie.TickLabel("10", "")]
    # auto: tiny spans → scientific (oracle: rich("1","×10",sup("−9")) etc.)
    auto2 = WasmMakie.format_ticks_auto([0.0, 1.0e-9, 2.0e-9])
    @test auto2 == [WasmMakie.TickLabel("0", ""),
                    WasmMakie.TickLabel("1×10", "−9"),
                    WasmMakie.TickLabel("2×10", "−9")]
    # mixed-precision scientific keeps aligned padding (upstream can_strip=false)
    auto3 = WasmMakie.format_ticks_auto([1.5e-7, 2.0e-7])
    @test auto3[1].sup == "−7" && auto3[2].sup == "−7"
    @test endswith(auto3[1].text, "×10") && startswith(auto3[1].text, "1.5")
end

@testset "colormaps + interpolation (C-004) — Makie oracle hardcoded" begin
    @test length(WasmMakie.VIRIDIS) == 256
    @test all(c -> all(0.0 .<= c .<= 1.0), WasmMakie.VIRIDIS)

    # oracle samples captured from Makie.interpolated_getindex(to_colormap(:viridis), t)
    oracle = [
        (0.0, (0.26700401306152344, 0.004873999860137701, 0.3294149935245514, 1.0)),
        (0.25, (0.23022274672985077, 0.32129722833633423, 0.5454879999160767, 1.0)),
        (0.5, (0.12814849615097046, 0.565106987953186, 0.5508924722671509, 1.0)),
        (0.75, (0.36285924911499023, 0.7866950035095215, 0.386588990688324, 1.0)),
        (1.0, (0.9932479858398438, 0.9061570167541504, 0.14393599331378937, 1.0)),
        (0.123, (0.2793009877204895, 0.17238421738147736, 0.4812380075454712, 1.0)),
    ]
    for (t, want) in oracle
        got = WasmMakie.colormap_color(t)
        @test all(abs.(got .- want) .< 1e-7)  # Float64 lerp vs Makie's Float32
    end

    # range-normalized variant clamps and maps
    @test WasmMakie.interpolated_getindex(WasmMakie.VIRIDIS, 5.0, 0.0, 10.0) ==
          WasmMakie.colormap_color(0.5)
    @test WasmMakie.interpolated_getindex(WasmMakie.VIRIDIS, -3.0, 0.0, 10.0) ==
          WasmMakie.colormap_color(0.0)
    @test_throws ErrorException WasmMakie.interpolated_getindex(WasmMakie.VIRIDIS, 1.0, 2.0, 2.0)
    @test_throws ErrorException WasmMakie.interpolated_getindex(WasmMakie.VIRIDIS, NaN)
end

# C-005 kernel at top level so WasmTarget gets clean typed IR
function geom_kernel_c005(x::Float64, y::Float64)::Float64
    T = WasmMakie.mat4_mul(WasmMakie.mat4_viewport(640.0, 480.0),
                           WasmMakie.mat4_translation_scale(0.1, 0.2, 0.0, 2.0, 2.0, 1.0))
    p = WasmMakie.project_px(T, x, y)
    return p.x + p.y
end

@testset "geometry types + WasmTarget decision (C-005)" begin
    M = WasmMakie
    # identity behaves
    v = M.mat4_vec4(M.MAT4_I, M.Vec4(1.0, 2.0, 3.0, 1.0))
    @test (v.x, v.y, v.z, v.w) == (1.0, 2.0, 3.0, 1.0)
    # column-major getindex
    T = M.mat4_translation_scale(7.0, 8.0, 9.0, 2.0, 3.0, 4.0)
    @test T[1, 1] == 2.0 && T[2, 2] == 3.0 && T[3, 3] == 4.0
    @test T[1, 4] == 7.0 && T[2, 4] == 8.0 && T[3, 4] == 9.0
    # composition: scale then translate
    p = M.mat4_vec4(T, M.Vec4(1.0, 1.0, 1.0, 1.0))
    @test (p.x, p.y, p.z) == (9.0, 11.0, 13.0)
    # mat4_mul against hand-computed product
    A = M.mat4_translation_scale(1.0, 0.0, 0.0, 2.0, 1.0, 1.0)
    B = M.mat4_translation_scale(0.0, 3.0, 0.0, 1.0, 5.0, 1.0)
    AB = M.mat4_mul(A, B)
    q = M.mat4_vec4(AB, M.Vec4(1.0, 1.0, 0.0, 1.0))
    qq = M.mat4_vec4(A, M.mat4_vec4(B, M.Vec4(1.0, 1.0, 0.0, 1.0)))
    @test (q.x, q.y) == (qq.x, qq.y)
    # viewport: ndc (0,0) → center, (1,1) → top-right (y-down)
    V = M.mat4_viewport(640.0, 480.0)
    c = M.project_px(V, 0.0, 0.0)
    @test (c.x, c.y) == (320.0, 240.0)
    tr = M.project_px(V, 1.0, 1.0)
    @test (tr.x, tr.y) == (640.0, 0.0)

    # THE DECISION GATE: the geometry kernel compiles through WasmTarget and
    # matches native bit-for-bit in node. (StaticArrays' equivalent compiled
    # at 14.6KB vs our 4.7KB; ntuple-closure form overflowed the compiler —
    # WTGAP queued for W-003.)
    native = geom_kernel_c005(0.25, -0.5)
    bytes = WasmTarget.compile(geom_kernel_c005, (Float64, Float64))
    @test length(bytes) > 8 && length(bytes) < 10_000
    dir = mktempdir()
    wasm_path = joinpath(dir, "geom.wasm")
    write(wasm_path, bytes)
    out = read(`node -e "
      const fs = require('fs');
      WebAssembly.instantiate(fs.readFileSync('$wasm_path'), {Math:{pow:Math.pow}}).then(m => {
        console.log(m.instance.exports.geom_kernel_c005(0.25, -0.5));
      });"`, String)
    @test parse(Float64, strip(out)) === native
end

@testset "plot structs + API (C-007)" begin
    fig = Figure()
    ax = Axis(fig[1, 1])

    # lines!: cycle color, range input, function input
    l1 = lines!(ax, 0:0.5:10, [sin(v) for v in 0:0.5:10])
    @test l1.color == cycle_color(1)
    @test l1.linewidth == 1.5 && l1.linestyle == WasmMakie.LINESTYLE_SOLID
    @test length(l1.x) == 21 && l1.x[2] == 0.5
    l2 = lines!(ax, 0:1.0:5, sin; color = :red, linestyle = :dash)
    @test l2.color == (1.0, 0.0, 0.0, 1.0)
    @test l2.linestyle == WasmMakie.LINESTYLE_DASH
    @test l2.y[1] == sin(0.0) && l2.y[end] == sin(5.0)

    # scatter!: third plot continues the cycle
    s1 = scatter!(ax, [1, 2, 3], [4, 5, 6])
    @test s1.color == cycle_color(3)
    @test s1.markersize == 9.0 && s1.marker == WasmMakie.MARKER_CIRCLE
    @test s1.strokewidth == 0.0

    # barplot!: defaults from Makie (gap 0.2), limits reach to 0 AND include
    # the bar rectangles (width (1-gap)·step = 0.8 → ±0.4; L-004 oracle fix)
    b1 = barplot!(ax, [1, 2], [3.0, -1.0]; color = (0.0, 0.0, 1.0, 1.0))
    @test b1.gap == 0.2
    @test b1.width == 0.8
    @test WasmMakie.data_limits(b1) == (0.6, 2.4, -1.0, 3.0)

    # heatmap!: centers→edges conversion + edges passthrough
    h1 = heatmap!(ax, [1.0, 2.0], [10.0, 20.0], [1.0 2.0; 3.0 4.0])
    @test h1.xs == [0.5, 1.5, 2.5]          # centers expanded to edges
    @test h1.ys == [5.0, 15.0, 25.0]
    h2 = heatmap!(ax, [0, 1, 2], [0, 1, 2], [1.0 2.0; 3.0 4.0])
    @test h2.xs == [0.0, 1.0, 2.0]          # already edges
    @test isnan(h2.colorrange_min)

    # image!: column-major flattening
    px = [(1.0, 0.0, 0.0, 1.0) (0.0, 1.0, 0.0, 1.0);
          (0.0, 0.0, 1.0, 1.0) (1.0, 1.0, 0.0, 1.0)]
    i1 = image!(ax, (0, 10), (0, 20), px)
    @test i1.ni == 2 && i1.nj == 2
    @test i1.pixels[1] == (1.0, 0.0, 0.0, 1.0)   # [1,1]
    @test i1.pixels[2] == (0.0, 0.0, 1.0, 1.0)   # [2,1] (column-major)
    @test WasmMakie.data_limits(i1) == (0.0, 10.0, 0.0, 20.0)

    # draw order tracks every call in sequence
    @test ax.plot_order == [
        (WasmMakie.PLOT_LINES, 1), (WasmMakie.PLOT_LINES, 2),
        (WasmMakie.PLOT_SCATTER, 1), (WasmMakie.PLOT_BARPLOT, 1),
        (WasmMakie.PLOT_HEATMAP, 1), (WasmMakie.PLOT_HEATMAP, 2),
        (WasmMakie.PLOT_IMAGE, 1),
    ]

    # NaN-tolerant data limits
    l3 = lines!(ax, [1.0, NaN, 3.0], [5.0, NaN, 7.0])
    @test WasmMakie.data_limits(l3) == (1.0, 3.0, 5.0, 7.0)

    # named colors error loudly on unknowns
    @test_throws ErrorException lines!(ax, [1, 2], [1, 2]; color = :no_such_color)
end

@testset "axis resolution: limits + locateticks + protrusions (C-008)" begin
    # locateticks parity — oracle outputs from Makie.locateticks(lo, hi, 5)
    L = WasmMakie.locateticks
    @test L(0.9, 3.1, 5) == [1.0, 1.5, 2.0, 2.5, 3.0]
    @test L(0.0, 10.0, 5) == [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]
    @test L(4.8, 9.2, 5) == [5.0, 6.0, 7.0, 8.0, 9.0]
    @test L(-5.0, 5.0, 5) == [-4.0, -2.0, 0.0, 2.0, 4.0]
    @test L(0.001, 0.0023, 5) == [0.0012, 0.0015, 0.0018, 0.0021]
    @test L(-273.15, 0.0, 5) == [-240.0, -180.0, -120.0, -60.0, 0.0]
    @test L(0.0, 1.0e6, 5) == [0.0, 200000.0, 400000.0, 600000.0, 800000.0, 1.0e6]
    @test L(2.5, 7.5, 5) == [3.0, 4.0, 5.0, 6.0, 7.0]

    # final_limits — oracle: Makie ax.finallimits
    fig = Figure()
    ax = Axis(fig[1, 1])
    lines!(ax, [1.0, 2.0, 3.0], [5.0, 9.0, 7.0])
    lims = WasmMakie.final_limits(ax)
    @test all(abs.(lims .- (0.9, 3.1, 4.8, 9.2)) .< 1e-6)
    # empty axis → (0, 10, 0, 10)
    ax2 = Axis(Figure()[1, 1])
    @test WasmMakie.final_limits(ax2) == (0.0, 10.0, 0.0, 10.0)
    # degenerate y span → default (oracle behavior)
    ax3 = Axis(Figure()[1, 1])
    lines!(ax3, [1.0, 2.0], [5.0, 5.0])
    @test WasmMakie.final_limits(ax3)[3:4] == (0.0, 10.0)
    # user override wins per side
    ax.ymin = 0.0
    @test WasmMakie.final_limits(ax)[3] == 0.0
    @test abs(WasmMakie.final_limits(ax)[4] - 9.2) < 1e-6
    ax.ymin = NaN

    # resolve_axis end-to-end
    res = WasmMakie.resolve_axis(ax)
    @test res.xticks == [1.0, 1.5, 2.0, 2.5, 3.0]
    @test all(res.xmin .<= res.xticks .<= res.xmax)
    @test res.xticklabels[1] == WasmMakie.TickLabel("1.0", "")
    @test length(res.yticklabels) == length(res.yticks)

    # protrusions: EXACT Makie parity (T-005; oracle 2026-06-11: empty default
    # axis → yticks [0,5,10], labels 0/5/10, left 24.568, bottom 23.31)
    res2 = WasmMakie.resolve_axis(ax2)
    @test res2.xticks == [0.0, 5.0, 10.0]               # Wilkinson, not locateticks
    @test [l.text for l in res2.xticklabels] == ["0", "5", "10"]
    @test abs(res2.prot.b - 23.31) < 1e-9
    @test abs(res2.prot.l - 24.568) < 1e-3              # Makie reports Float32
    @test res2.prot.t == 0.0 && res2.prot.r == 0.0
    # labels/title add protrusion
    ax4 = Axis(Figure()[1, 1]; title = "T", xlabel = "x", ylabel = "y")
    res4 = WasmMakie.resolve_axis(ax4)
    @test res4.prot.b > res2.prot.b
    @test res4.prot.l > res2.prot.l
    @test res4.prot.t > 0.0
end


@testset "axis decorations complete (L-001)" begin
    ax = Axis(Figure()[1, 1]; title = "T", subtitle = "S", xlabel = "x", ylabel = "y")
    @test ax.titlesize == 14.0 && ax.subtitlesize == 14.0   # @inherit(:fontsize)
    @test ax.xgridvisible && !ax.xminorgridvisible && !ax.xminorticksvisible

    # subtitle adds top protrusion on top of the title block
    res = WasmMakie.resolve_axis(ax)
    axt = Axis(Figure()[1, 1]; title = "T", xlabel = "x", ylabel = "y")
    rest = WasmMakie.resolve_axis(axt)
    @test res.prot.t ≈ rest.prot.t + 1.165 * 14.0   # subtitlegap 0

    # hide functions flip the right flags and shrink protrusions
    hidedecorations!(ax)
    @test !ax.xlabelvisible && !ax.yticklabelsvisible && !ax.xgridvisible
    @test ax.titlevisible    # title NOT hidden (Makie parity)
    resh = WasmMakie.resolve_axis(ax)
    @test resh.prot.b == 0.0 && resh.prot.l == 0.0
    hidespines!(ax, :t, :r)
    @test !ax.topspinevisible && !ax.rightspinevisible && ax.leftspinevisible

    # minor positions: IntervalsBetween(2) = midpoints
    @test WasmMakie._minor_positions([0.0, 1.0, 2.0], Int64(2)) == [0.5, 1.5]
    @test WasmMakie._minor_positions([0.0, 1.0], Int64(4)) == [0.25, 0.5, 0.75]
    @test isempty(WasmMakie._minor_positions([0.0, 1.0], Int64(1)))

    # render stream reflects visibility: hidden axis => no text at all
    fig = Figure(size = (300, 200))
    axh = Axis(fig[1, 1])
    lines!(axh, [0.0, 1.0], [0.0, 1.0])
    hidedecorations!(axh)
    hidespines!(axh)
    r = RecordingCtx(); render!(fig, r)
    @test !any(c -> c.op === :fill_text_buf, r.commands)
    # bold title op present when titled
    fig2 = Figure(size = (300, 200))
    ax4 = Axis(fig2[1, 1]; title = "T")
    ax4.xminorgridvisible = true
    lines!(ax4, [0.0, 1.0], [0.0, 1.0])
    r2 = RecordingCtx(); render!(fig2, r2)
    @test any(c -> c.op === :set_font && c.iargs[2] == 700, r2.commands)
end

@testset "axislegend (L-002)" begin
    fig = Figure(size = (300, 200))
    ax = Axis(fig[1, 1])
    lines!(ax, [0.0, 1.0], [0.0, 1.0]; label = "a")
    scatter!(ax, [0.5], [0.5]; label = "b")
    barplot!(ax, [1.0], [1.0])           # unlabeled — excluded
    @test !ax.legend_active
    axislegend(ax; position = :lb, nbanks = 2)
    @test ax.legend_active && ax.legend_halign == 0 && ax.legend_valign == 0
    @test ax.legend_nbanks == 2
    r = RecordingCtx(); render!(fig, r)
    # legend frame stroke + two label texts drawn after the plots
    texts = count(c -> c.op === :fill_text_buf, r.commands)
    @test texts >= 2   # tick labels + 2 legend labels
    # no labels -> no legend even when active
    fig2 = Figure(size = (300, 200))
    ax2 = Axis(fig2[1, 1])
    lines!(ax2, [0.0, 1.0], [0.0, 1.0])
    axislegend(ax2)
    r2 = RecordingCtx(); render!(fig2, r2)
    rn = RecordingCtx()
    fig3 = Figure(size = (300, 200))
    ax3 = Axis(fig3[1, 1])
    lines!(ax3, [0.0, 1.0], [0.0, 1.0])
    render!(fig3, rn)
    @test length(r2.commands) == length(rn.commands)   # legend was a no-op
end

@testset "Colorbar (L-003)" begin
    fig = Figure(size = (300, 200))
    ax = Axis(fig[1, 1])
    hm = heatmap!(ax, [0, 1, 2, 3], [0, 1, 2], [1.0 4.0; 2.0 5.0; 3.0 6.0])
    cb = Colorbar(fig[1, 2], hm)
    @test cb.lo == 1.0 && cb.hi == 6.0      # linked to heatmap data range
    @test cb.vertical
    @test length(fig.colorbars) == 1
    @test WasmMakie.grid_extents(fig) == (1, 2)
    # explicit limits + label
    fig2 = Figure(size = (300, 200))
    Axis(fig2[1, 1])
    cb2 = Colorbar(fig2[1, 2]; limits = (0.0, 10.0), label = "level")
    p = WasmMakie._colorbar_protrusions(cb2)
    @test p.r > 5.0   # ticks + labels + label space on the right
    @test p.l == 0.0 && p.t == 0.0
    # stream: image strip + spine + ticks + label drawn
    r = RecordingCtx(); render!(fig, r)
    @test any(c -> c.op === :img_buf_new, r.commands)
    @test any(c -> c.op === :draw_image_buf, r.commands)
    # horizontal variant renders too
    fig3 = Figure(size = (300, 200))
    Axis(fig3[2, 1])
    Colorbar(fig3[1, 1]; limits = (0.0, 1.0), vertical = false)
    r3 = RecordingCtx(); render!(fig3, r3)
    @test any(c -> c.op === :img_buf_new, r3.commands)
end

@testset "GridLayout spans + sizes (L-004)" begin
    fig = Figure(size = (400, 300))
    ax = Axis(fig[1, 1:2])
    @test ax.row == 1 && ax.col == 1 && ax.row2 == 1 && ax.col2 == 2
    Axis(fig[2, 1]); Axis(fig[2, 2])
    @test WasmMakie.grid_extents(fig) == (2, 2)
    colsize!(fig, 1, Relative(0.3))
    rowsize!(fig, 2, 120)
    @test fig.colsizes[1].kind == WasmMakie.SIZE_RELATIVE
    @test fig.rowsizes[2].kind == WasmMakie.SIZE_FIXED && fig.rowsizes[2].value == 120.0
    r = RecordingCtx(); render!(fig, r)
    @test length(r.commands) > 100   # renders without error
    # span rect really unions cells: the wide axis bg covers > half the width
    bg = nothing
    count_fr = 0
    for c in r.commands
        if c.op === :fill_rect
            count_fr += 1
            count_fr == 2 && (bg = c)   # 1st = figure bg, 2nd = first axis bg
        end
    end
    @test bg !== nothing && bg.fargs[3] > 200.0   # spans both columns of a 400w figure
    # vertical span for colorbars
    fig2 = Figure(size = (300, 300))
    Axis(fig2[1, 1]); Axis(fig2[2, 1])
    cb = Colorbar(fig2[1:2, 2]; limits = (0.0, 1.0))
    @test cb.row == 1 && cb.row2 == 2
    r2 = RecordingCtx(); render!(fig2, r2)
    @test any(c -> c.op === :img_buf_new, r2.commands)
end

@testset "wave-1 annotation recipes (R-002 partial)" begin
    fig = Figure(size = (300, 200))
    ax = Axis(fig[1, 1])
    lines!(ax, [0.0, 2.0], [0.0, 2.0])
    h = hlines!(ax, [0.5, 1.5]; color = :red)
    @test h.horizontal && h.values == [0.5, 1.5]
    v = vlines!(ax, 1.0)
    @test !v.horizontal
    sp = hspan!(ax, 0.2, 0.4; color = (0.1, 0.2, 0.3, 0.4))
    @test sp.los == [0.2] && sp.his == [0.4]
    ab = ablines!(ax, 1.0, -0.5)
    @test ab.intercepts == [1.0] && ab.slopes == [-0.5]
    sg = linesegments!(ax, [0.0, 1.0, 1.0, 2.0], [0.0, 0.0, 1.0, 1.0])
    @test length(sg.x) == 4
    # limits: hlines extend y only; ablines never affect autolimits
    axh = Axis(Figure()[1, 1])
    lines!(axh, [0.0, 1.0], [0.0, 1.0])
    hlines!(axh, [5.0])
    lims = WasmMakie.final_limits(axh)
    @test lims[4] > 5.0          # y grew to include the hline
    @test lims[2] < 1.1          # x untouched
    axa = Axis(Figure()[1, 1])
    lines!(axa, [0.0, 1.0], [0.0, 1.0])
    ablines!(axa, 100.0, 0.0)
    @test WasmMakie.final_limits(axa)[4] < 1.1   # ablines ignored
    # scatterlines = lines + scatter sharing color
    axs = Axis(Figure()[1, 1])
    sl = scatterlines!(axs, [0.0, 1.0], [0.0, 1.0])
    @test length(axs.lines) == 1 && length(axs.scatters) == 1
    @test axs.lines[1].color == axs.scatters[1].color
    # render smoke
    r = RecordingCtx(); render!(fig, r)
    @test length(r.commands) > 120
end

@testset "wave-1 stats recipes (R-002 complete)" begin
    ax = Axis(Figure()[1, 1])
    st = stairs!(ax, [0.0, 1.0, 2.0], [0.0, 1.0, 0.5])
    # :pre expansion doubles interior points (Makie stairs.jl verbatim)
    @test st.x == [0.0, 0.0, 1.0, 1.0, 2.0]
    @test st.y == [0.0, 1.0, 1.0, 0.5, 0.5]
    st2 = stairs!(ax, [0.0, 1.0, 2.0], [0.0, 1.0, 0.5]; step = :post)
    @test st2.x == [0.0, 1.0, 1.0, 2.0, 2.0]
    @test st2.y == [0.0, 0.0, 1.0, 1.0, 0.5]
    st3 = stairs!(ax, [0.0, 2.0], [0.0, 1.0]; step = :center)
    @test st3.x == [0.0, 1.0, 1.0, 2.0]

    # hist: right-open edge binning (0.2 belongs to bin 2, not 1). Counts
    # match Makie's range-based edges (ULP-sensitive: edges[3] =
    # 0.30000000000000004 puts 0.3 in bin 2 — corpus oracle confirms, 0.217)
    axh = Axis(Figure()[1, 1])
    hb = hist!(axh, [0.1, 0.2, 0.2, 0.3, 0.45, 0.5, 0.5, 0.55, 0.7, 0.9]; bins = 8)
    @test hb.y == [1.0, 3.0, 0.0, 3.0, 1.0, 1.0, 0.0, 1.0]
    @test sum(hb.y) == 10.0
    @test hb.width ≈ (nextfloat(0.9) - 0.1) / 8
    @test hb.color[4] == 0.8   # patchcolor cycle alpha

    # errorbars/rangebars are segment pairs
    axe = Axis(Figure()[1, 1])
    eb = errorbars!(axe, [1.0], [2.0], [0.5])
    @test eb.x == [1.0, 1.0] && eb.y == [1.5, 2.5]
    rb = rangebars!(axe, [3.0], [0.0], [1.0])
    @test rb.y == [0.0, 1.0]

    # stem = trunk + stems + heads
    axs = Axis(Figure()[1, 1])
    stem!(axs, [1.0, 2.0], [0.5, -0.5])
    @test length(axs.lines) == 1 && length(axs.segments) == 1 && length(axs.scatters) == 1

    # density: vendored Silverman KDE integrates to ~1
    axd = Axis(Figure()[1, 1])
    d = density!(axd, [0.1, 0.2, 0.25, 0.3, 0.5, 0.55, 0.6, 0.9])
    @test length(d.x) == 200
    stepw = d.x[2] - d.x[1]
    @test abs(sum(d.y) * stepw - 1.0) < 0.02
    @test all(d.y .>= 0.0)
end

@testset "wave-2 composites (R-003 partial)" begin
    ax = Axis(Figure()[1, 1])
    b = band!(ax, [0.0, 1.0], [0.0, 0.5], [1.0, 1.5])
    @test b.color[4] == 0.8
    @test WasmMakie.data_limits(b) == (0.0, 1.0, 0.0, 1.5)

    axp = Axis(Figure()[1, 1])
    pie!(axp, [1.0, 1.0, 2.0])
    @test length(axp.polys) == 3
    # half the circle for the weight-2 slice: center + 181 arc points
    @test length(axp.polys[3].xs) == 182
    @test WasmMakie.data_limits(axp.polys[1])[1] >= -1.0

    axb = Axis(Figure()[1, 1])
    boxplot!(axb, [1.0, 1, 1, 1, 1, 1], [1.0, 2, 3, 4, 5, 19])
    @test length(axb.polys) == 1          # one box
    @test length(axb.scatters) == 1       # 19 is an outlier (1.5 IQR fence)
    @test axb.scatters[1].y == [19.0]
    @test length(axb.segments) == 1       # whiskers + median
    # box spans q25..q75 of [1..5,19]
    @test minimum(axb.polys[1].ys) == WasmMakie._quantile7([1.0, 2, 3, 4, 5, 19], 0.25)

    axv = Axis(Figure()[1, 1])
    violin!(axv, [1.0, 1, 1, 1, 1], [1.0, 2, 3, 4, 5])
    @test length(axv.polys) == 1
    @test length(axv.polys[1].xs) == 400  # mirrored 200-point KDE
    # body is symmetric about the group center
    @test abs((maximum(axv.polys[1].xs) - 1.0) - (1.0 - minimum(axv.polys[1].xs))) < 1e-9
end

@testset "grouped/stacked bars + crossbar + series + waterfall (R-003)" begin
    # dodge: Makie shift/scale formulas
    ax = Axis(Figure()[1, 1])
    b = barplot!(ax, [1.0, 1.0], [2.0, 3.0]; dodge = [1, 2])
    # width (1-gap)*1 = 0.8; dw = (1-0.03)/2 = 0.485; shifts ±(dw+gap)/2-ish
    @test b.width ≈ 0.8 * 0.485
    @test b.x[1] < 1.0 < b.x[2]
    @test b.x[2] - b.x[1] ≈ 0.8 * (0.485 + 0.03)
    # stack: cumulative from/to per x
    ax2 = Axis(Figure()[1, 1])
    b2 = barplot!(ax2, [1.0, 1.0, 2.0, 2.0], [2.0, 3.0, 1.0, 2.0]; stack = [1, 2, 1, 2])
    @test b2.fillto == [0.0, 2.0, 0.0, 1.0]
    @test b2.y == [2.0, 5.0, 1.0, 3.0]
    @test WasmMakie.data_limits(b2)[4] == 5.0
    # waterfall: running-sum spans
    ax3 = Axis(Figure()[1, 1])
    w = waterfall!(ax3, [1.0, 2.0, 3.0], [2.0, -1.0, 3.0])
    @test w.fillto == [0.0, 2.0, 1.0]
    @test w.y == [2.0, 1.0, 4.0]
    # crossbar: box poly + midline segments
    ax4 = Axis(Figure()[1, 1])
    crossbar!(ax4, [1.0], [2.0], [1.0], [3.0])
    @test length(ax4.polys) == 1 && length(ax4.segments) == 1
    @test extrema(ax4.polys[1].ys) == (1.0, 3.0)
    # series: one cycle-colored line per row
    ax5 = Axis(Figure()[1, 1])
    series!(ax5, [1.0 2.0; 3.0 4.0])
    @test length(ax5.lines) == 2
    @test ax5.lines[1].color != ax5.lines[2].color
end

@testset "contour recipes (R-004)" begin
    # marching squares on a known saddle: z = x*y on [-1,1]^2, level 0 →
    # the two axes are the isolines
    xs = Float64[-1.0, 0.0, 1.0]
    z = Float64[1.0, 0.0, -1.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0]  # x*y column-major
    lines = WasmMakie.contour_lines(xs, xs, z, Int64(3), Int64(3), 0.0)
    @test !isempty(lines)
    for line in lines
        for (px, py) in line
            @test abs(px * py) < 1e-9   # all crossings sit on the axes
        end
    end
    # closed contour: radial bump, inner level traces a loop
    n = 9
    g = collect(range(-1.0, 1.0, length = n))
    zr = Vector{Float64}(undef, n * n)
    for j in 1:n, i in 1:n
        zr[i + (j - 1) * n] = exp(-(g[i]^2 + g[j]^2) * 3.0)
    end
    loops = WasmMakie.contour_lines(g, g, zr, Int64(n), Int64(n), 0.5)
    @test length(loops) == 1
    @test loops[1][1] == loops[1][end]   # closed (loopback)
    # contourlevels: n interior levels
    ls = WasmMakie.contourlevels(0.0, 1.0, Int64(4))
    @test ls ≈ [0.2, 0.4, 0.6, 0.8]
    # recipes build plots
    ax = Axis(Figure()[1, 1])
    contour!(ax, g, g, zr, Int64(n), Int64(n))
    @test length(ax.lines) >= 5
    ax2 = Axis(Figure()[1, 1])
    contourf!(ax2, g, g, zr, Int64(n), Int64(n); upsample = 2)
    @test length(ax2.heatmaps) == 1
    # band-midpoint quantization: every fine value is one of the midpoints
    hm = ax2.heatmaps[1]
    zmin, zmax = extrema(zr)
    bw = (zmax - zmin) / 10
    for v in hm.values
        rem = (v - zmin) / bw - 0.5
        @test abs(rem - round(rem)) < 1e-9
    end
end

@testset "mesh rasterizer + surface (R-005)" begin
    # analytic oracle: right triangle (1,1)-(9,1)-(1,9) into a 10×10 buffer
    w = Int64(10); h = Int64(10)
    pix = fill((0.0, 0.0, 0.0, 0.0), 100)
    depth = fill(Inf, 100)
    WasmMakie.rasterize_mesh!(pix, depth, w, h,
        [1.0, 9.0, 1.0], [1.0, 1.0, 9.0], [0.0, 0.0, 0.0],
        [1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0], [1.0, 1.0, 1.0],
        Int64[1, 2, 3])
    @test pix[2 + 1 * 10][4] == 1.0          # (2,2) inside
    @test pix[9 + 8 * 10][4] == 0.0          # (9,9) outside the hypotenuse
    # Gouraud: vertex corners carry their colors
    @test pix[1 + 0 * 10][1] ≈ 1.0           # (1,1) red vertex
    @test pix[9 + 0 * 10][2] ≈ 1.0           # (9,1) green vertex
    # barycentric interpolation sums to 1 → rgb sums to 1 inside
    c = pix[3 + 2 * 10]
    @test c[1] + c[2] + c[3] ≈ 1.0

    # depth test: nearer (smaller z) triangle wins
    pix2 = fill((0.0, 0.0, 0.0, 0.0), 100)
    depth2 = fill(Inf, 100)
    WasmMakie.rasterize_mesh!(pix2, depth2, w, h,
        [1.0, 9.0, 1.0, 1.0, 9.0, 1.0], [1.0, 1.0, 9.0, 1.0, 1.0, 9.0],
        [1.0, 1.0, 1.0, 0.0, 0.0, 0.0],
        [1.0, 1.0, 1.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
        Int64[1, 2, 3, 4, 5, 6])
    @test pix2[2 + 1 * 10][2] == 1.0         # green (z=0) in front of red (z=1)

    # winding-agnostic: CW face still fills
    pix3 = fill((0.0, 0.0, 0.0, 0.0), 100)
    depth3 = fill(Inf, 100)
    WasmMakie.rasterize_mesh!(pix3, depth3, w, h,
        [1.0, 1.0, 9.0], [1.0, 9.0, 1.0], [0.0, 0.0, 0.0],
        [1.0, 1.0, 1.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [1.0, 1.0, 1.0],
        Int64[1, 2, 3])
    @test pix3[2 + 1 * 10][1] == 1.0

    # recipes
    ax = Axis(Figure()[1, 1])
    m = mesh!(ax, [0.0, 1.0, 0.5], [0.0, 0.0, 1.0], [1, 2, 3]; color = :red)
    @test length(m.faces) == 3
    @test WasmMakie.data_limits(m) == (0.0, 1.0, 0.0, 1.0)
    ax2 = Axis(Figure()[1, 1])
    xs = collect(0.0:0.5:2.0)
    sp = surface!(ax2, xs, xs, [sin(x) * cos(y) for x in xs, y in xs])
    @test length(sp.vx) == 25
    @test length(sp.faces) == 2 * 16 * 3     # two triangles per cell
    @test length(ax2.meshes) == 1
    @test meshscatter!(Axis(Figure()[1, 1]), [1.0], [2.0]) isa WasmMakie.ScatterPlot

    # browser: the Gouraud triangle draws real pixels
    fig = Figure(size = (200.0, 150.0))
    axb = Axis(fig[1, 1])
    mesh!(axb, [0.0, 1.0, 0.5], [0.0, 0.0, 1.0], Int64[1, 2, 3];
          color = [:red, :green, :blue])
    r = RecordingCtx(); render!(fig, r)
    res = render_commands(to_json(r); width = 200, height = 150,
                          probes = [(100, 100)])
    if res === nothing
        @test_skip "playwright unavailable"
    else
        px = res.pixels[(100, 100)]
        @test px[1] + px[2] + px[3] < 720   # inked (not white) near center
    end
end

# E-001 wasm-acid kernel (top-level; the README example program)
function e001_show()
    fig = Figure(size = (300.0, 200.0))
    ax = Axis(fig[1, 1])
    lines!(ax, [0.0, 1.0, 2.0], [0.0, 1.0, 0.5])
    render!(fig, WasmCtx())
    return Int64(0)
end

@testset "embedding contract GA (E-001)" begin
    fig = Figure(size = (200, 150))
    lines!(Axis(fig[1, 1]), [0.0, 1.0, 2.0], [0.0, 1.0, 0.5]; color = :red)

    snip = html_snippet(fig; id = "c")   # render_page.mjs probes #c
    @test occursin("<canvas id=\"c\" width=\"200\" height=\"150\">", snip)
    @test occursin("canvas2d_imports", snip)        # glue embedded
    @test occursin("replayCommands", snip)          # replayer embedded
    @test occursin("data:font/otf;base64,", snip)   # fonts embedded
    @test !occursin("http://", snip) && !occursin("src=", snip)  # self-contained
    # auto ids are unique
    @test html_snippet(fig) != html_snippet(fig)
    # fonts can be omitted for hosts that load them once globally
    @test !occursin("data:font/otf", html_snippet(fig; fonts = false))

    # MIME show emits the snippet (notebooks/docs get inline figures)
    io = IOBuffer()
    show(io, MIME"text/html"(), fig)
    @test occursin("wasmmakie-figure", String(take!(io)))

    # acid test 1 (STATIC): plain HTML file + snippet shows the plot
    page(s) = """
    <!doctype html><html><body>
    $(s)
    <script>
    window.__done = false;
    (function poll() {
      const c = document.querySelector("canvas");
      if (c && c.dataset.wasmmakieDone === "1") { window.__done = true; }
      else { setTimeout(poll, 20); }
    })();
    </script></body></html>
    """
    dir = mktempdir()
    html_path = joinpath(dir, "static.html"); write(html_path, page(snip))
    png_path = joinpath(dir, "static.png")
    script = joinpath(dirname(@__DIR__), "assets", "render_page.mjs")
    out = IOBuffer()
    proc = run(pipeline(ignorestatus(`node $script $html_path $png_path "[[5,5],[100,75]]"`); stdout = out))
    if proc.exitcode == 2
        @test_skip "playwright unavailable"
    else
        sout = String(take!(out))
        @test proc.exitcode == 0
        @test occursin("PROBE 5,5 = 255,255,255,255", sout)   # figure bg drawn
    end

    # acid test 2 (WASM): host-compiled module + wasm_html_snippet — the
    # README plain-HTML example, verified end to end
    bytes = compile_with_canvas(Any[(e001_show, (), "show")])
    wsnip = wasm_html_snippet(bytes, "show"; width = 300, height = 200, id = "c")
    @test occursin("WebAssembly.instantiate", wsnip)
    @test occursin("canvas id=\"c\"", wsnip)
    html_path2 = joinpath(dir, "wasm.html"); write(html_path2, page(wsnip))
    png_path2 = joinpath(dir, "wasm.png")
    out2 = IOBuffer()
    proc2 = run(pipeline(ignorestatus(`node $script $html_path2 $png_path2 "[[5,5]]"`); stdout = out2))
    if proc2.exitcode == 2
        @test_skip "playwright unavailable"
    else
        sout2 = String(take!(out2))
        @test proc2.exitcode == 0
        @test occursin("PROBE 5,5 = 255,255,255,255", sout2)
    end
end

@testset "static-core render pipeline (C-009)" begin
    fig = Figure(size = (300, 200))
    ax = Axis(fig[1, 1]; title = "T", xlabel = "x", ylabel = "y")
    lines!(ax, [0.0, 1.0, 2.0], [0.0, 1.0, 0.5])
    scatter!(ax, [0.5, 1.5], [0.8, 0.2]; color = :red)
    r = RecordingCtx()
    render!(fig, r)
    @test length(r.commands) > 100
    @test r.commands[1].op === :set_fill_rgba       # background first
    @test r.commands[2].op === :fill_rect
    @test any(c -> c.op === :fill_text_buf, r.commands)   # labels drawn
    @test any(c -> c.op === :clip_nonzero, r.commands)    # plots clipped
    @test count(c -> c.op === :arc, r.commands) == 2      # two scatter circles

    # determinism: identical streams across renders (the wasm-diff invariant)
    r2 = RecordingCtx()
    render!(fig, r2)
    @test r.commands == r2.commands

    # browser pixels: first real WasmMakie-rendered figure
    res = render_commands(to_json(r); width = 300, height = 200,
                          probes = [(3, 3)])
    if res === nothing
        @test_skip "playwright unavailable"
    else
        @test res.pixels[(3, 3)] == (255, 255, 255, 255)  # figure bg
        img = res.png
        @test png_dims(img) == (300, 200)
        # decode-free色 checks via more probes
        res2 = render_commands(to_json(r); width = 300, height = 200, probes = Tuple{Int,Int}[])
        @test res2 !== nothing
    end
end


# WTGAP probe (see draw/lines.jl): const-global empty Vector reference
w001_const_global_probe() = Int64(length(WasmMakie.NO_DASH))

# W-001 kernel: the full draw layer through WasmCtx, compiled by WasmTarget
function w001_draw_program()
    ctx = WasmCtx()
    WasmMakie.set_fill_rgba(ctx, 255.0, 255.0, 255.0, 1.0)
    WasmMakie.fill_rect(ctx, 0.0, 0.0, 200.0, 150.0)
    pts = NTuple{2,Float64}[(20.0, 100.0), (80.0, 40.0), (140.0, 90.0)]
    WasmMakie.draw_lines!(ctx, pts, true, 0.0, 0.0, 1.0, 1.0, 6.0,
                          Float64[], Int64(0), Int64(0), 10.0)
    WasmMakie.draw_marker_circle!(ctx, 170.0, 40.0, 24.0, 0.0, 0.0, 24.0,
                                  1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0)
    WasmMakie.draw_poly_rect!(ctx, 20.0, 120.0, 60.0, 20.0,
                              0.0, 0.5, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0,
                              0.0, Float64[], Int64(0), Int64(0), 4.0)
    pixels = NTuple{4,Float64}[(1.0, 0.0, 1.0, 1.0), (0.0, 1.0, 1.0, 1.0)]
    WasmMakie.draw_image_scaled!(ctx, pixels, Int64(2), Int64(1), 150.0, 140.0, 40.0, -20.0, false)
    return Int64(0)
end

@testset "draw layer compiles + draws in wasm (W-001)" begin
    bytes = compile_with_canvas(Any[(w001_draw_program, (), "w001")])
    @test length(bytes) > 1000
    res = render_wasm(bytes, "w001"; width = 200, height = 150,
                      probes = [(3, 3), (40, 80), (170, 40), (50, 130), (155, 125), (185, 125)])
    if res === nothing
        @test_skip "playwright unavailable"
    else
        @test res.pixels[(3, 3)] == (255, 255, 255, 255)      # background
        @test res.pixels[(40, 80)] == (0, 0, 255, 255)        # blue polyline
        @test res.pixels[(170, 40)] == (255, 0, 0, 255)       # circle marker
        @test res.pixels[(50, 130)] == (0, 128, 0, 255)       # poly rect
        @test res.pixels[(155, 125)] == (255, 0, 255, 255)    # image px 1
        @test res.pixels[(185, 125)] == (0, 255, 255, 255)    # image px 2
    end

    # WTGAP(ffd3d052c6a4) FIXED (WasmTarget v0.3.1): const-global empty
    # Vector references now work compiled — pin the FIXED behavior
    bytes2 = compile_with_canvas(Any[(w001_const_global_probe, (), "kcg")])
    trapped = try
        render_wasm(bytes2, "kcg"; width = 20, height = 20, probes = [(2, 2)]) !== nothing
        false
    catch
        true
    end
    @test !trapped  # the gap is fixed; a re-trap would be an upstream regression
end


# W-002 kernel: the COMPLETE figure pipeline, compiled to wasm
function w002_figure()
    fig = Figure(size = (300.0, 200.0))
    ax = Axis(fig[1, 1])
    lines!(ax, [0.0, 1.0, 2.0], [0.0, 1.0, 0.5])
    render!(fig, WasmCtx())
    return Int64(0)
end

@testset "full figure pipeline in wasm + command-stream differential (W-002)" begin
    # host-side stream
    fig = Figure(size = (300.0, 200.0))
    ax = Axis(fig[1, 1])
    lines!(ax, [0.0, 1.0, 2.0], [0.0, 1.0, 0.5])
    r = RecordingCtx()
    render!(fig, r)
    host_json = to_json(r)

    # wasm-side stream (compiled module, instrumented glue, node)
    bytes = compile_with_canvas(Any[(w002_figure, (), "w002")])
    @test length(bytes) > 100_000
    dir = mktempdir()
    wasm_path = joinpath(dir, "w002.wasm"); write(wasm_path, bytes)
    glue_path = joinpath(dir, "glue.js"); write(glue_path, js_glue())
    checker = joinpath(@__DIR__, "wasm_stream_check.js")
    wasm_json = strip(read(`node $checker $wasm_path $glue_path w002`, String))

    # THE GATE: normalized streams must be EQUAL (wasm_diffpass)
    norm(j) = strip(read(`node -e "console.log(JSON.stringify(JSON.parse(process.argv[1])))" $j`, String))
    @test norm(host_json) == norm(wasm_json)

    # and the module draws real pixels in the browser
    res = render_wasm(bytes, "w002"; width = 300, height = 200, probes = [(3, 3)])
    if res === nothing
        @test_skip "playwright unavailable"
    else
        @test res.pixels[(3, 3)] == (255, 255, 255, 255)
    end
end


function w005_scatter()
    fig = Figure(size = (300.0, 200.0)); ax = Axis(fig[1, 1])
    scatter!(ax, [0.0, 1.0, 2.0], [0.5, 1.5, 1.0]; markersize = 14.0, color = :red)
    scatter!(ax, [0.5, 1.5], [1.2, 0.8]; marker = :rect, markersize = 10.0)
    render!(fig, WasmCtx()); return Int64(0)
end
function w005_bar()
    fig = Figure(size = (300.0, 200.0))
    ax = Axis(fig[1, 1])
    barplot!(ax, [1.0, 2.0, 3.0], [2.0, -1.0, 3.0]; color = :orange)
    render!(fig, WasmCtx()); return Int64(0)
end
# WTGAP(3aaa51b9a688, a9bf645b1003): heatmap/image kernels use the flat-vector
# overloads — Matrix construction fails wasm validation / traps.
function w005_heatmap()
    fig = Figure(size = (300.0, 200.0))
    ax = Axis(fig[1, 1])
    heatmap!(ax, [0.0, 1.0, 2.0, 3.0], [0.0, 1.0, 2.0],
             [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], Int64(3), Int64(2))
    render!(fig, WasmCtx()); return Int64(0)
end
function w005_image()
    fig = Figure(size = (300.0, 200.0))
    ax = Axis(fig[1, 1])
    px = NTuple{4,Float64}[(1.0, 0.0, 0.0, 1.0), (0.0, 0.0, 1.0, 1.0),
                           (0.0, 1.0, 0.0, 1.0), (1.0, 1.0, 0.0, 1.0)]
    image!(ax, (0.0, 2.0), (0.0, 2.0), px, Int64(2), Int64(2); interpolate = false)
    render!(fig, WasmCtx()); return Int64(0)
end
function w005_legend()
    fig = Figure(size = (300.0, 200.0))
    ax = Axis(fig[1, 1])
    lines!(ax, [0.0, 1.0, 2.0], [0.5, 1.5, 1.0]; label = "one")
    scatter!(ax, [0.5, 1.5], [1.2, 0.8]; label = "two", color = :red, markersize = 10.0)
    axislegend(ax)
    render!(fig, WasmCtx()); return Int64(0)
end
function w005_colorbar()
    fig = Figure(size = (300.0, 200.0))
    ax = Axis(fig[1, 1])
    hm = heatmap!(ax, [0.0, 1.0, 2.0, 3.0], [0.0, 1.0, 2.0],
                  [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], Int64(3), Int64(2))
    Colorbar(fig[1, 2], hm)
    render!(fig, WasmCtx()); return Int64(0)
end
function w005_annotations()
    fig = Figure(size = (300.0, 200.0))
    ax = Axis(fig[1, 1])
    lines!(ax, [0.0, 1.0, 2.0], [0.5, 1.5, 1.0])
    hlines!(ax, [1.0]; color = :red)
    vlines!(ax, [0.5]; color = :green, linestyle = :dash)
    hspan!(ax, 0.6, 0.8; color = (0.2, 0.4, 0.8, 0.3))
    ablines!(ax, 0.0, 0.7; color = :purple)
    linesegments!(ax, [0.2, 0.8, 1.2, 1.8], [1.4, 1.4, 0.2, 0.2])
    render!(fig, WasmCtx()); return Int64(0)
end
function w005_stats()
    fig = Figure(size = (300.0, 200.0))
    ax = Axis(fig[1, 1])
    stairs!(ax, [0.0, 1.0, 2.0, 3.0], [0.0, 1.0, 0.5, 0.8])
    hist!(ax, [0.1, 0.2, 0.2, 0.3, 0.45, 0.5, 0.5, 0.55, 0.7, 0.9]; bins = 4)
    errorbars!(ax, [0.5, 1.5], [0.5, 0.7], [0.1, 0.2]; color = :red)
    stem!(ax, [2.2, 2.6], [0.4, 0.9])
    density!(ax, [0.1, 0.2, 0.25, 0.3, 0.5, 0.55, 0.6, 0.9])
    render!(fig, WasmCtx()); return Int64(0)
end
function w005_composites()
    fig = Figure(size = (300.0, 200.0))
    ax = Axis(fig[1, 1])
    band!(ax, [0.0, 1.0, 2.0], [0.1, 0.3, 0.2], [0.5, 0.8, 0.6])
    boxplot!(ax, [3.0, 3.0, 3.0, 3.0, 3.0], [0.2, 0.4, 0.5, 0.6, 0.9])
    violin!(ax, [4.0, 4.0, 4.0, 4.0, 4.0], [0.3, 0.4, 0.5, 0.6, 0.7])
    pie!(Axis(fig[1, 2]), [3.0, 2.0, 1.0])
    render!(fig, WasmCtx()); return Int64(0)
end
function w005_groupedbars()
    fig = Figure(size = (300.0, 200.0))
    barplot!(Axis(fig[1, 1]), [1.0, 1.0, 2.0, 2.0], [2.0, 3.0, 1.0, 2.0];
             dodge = Int64[1, 2, 1, 2])
    barplot!(Axis(fig[1, 2]), [1.0, 1.0, 2.0, 2.0], [2.0, 3.0, 1.0, 2.0];
             stack = Int64[1, 2, 1, 2])
    waterfall!(Axis(fig[2, 1]), [1.0, 2.0, 3.0], [2.0, -1.0, 3.0])
    crossbar!(Axis(fig[2, 2]), [1.0, 2.0], [2.0, 3.0], [1.0, 2.0], [3.0, 4.0])
    render!(fig, WasmCtx()); return Int64(0)
end
function w005_contour()
    fig = Figure(size = (300.0, 200.0))
    xs = Float64[0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    z = Vector{Float64}(undef, 81)
    for j in 1:9
        for i in 1:9
            z[i + (j - 1) * 9] = sin(3.0 * xs[i]) * cos(3.0 * xs[j])
        end
    end
    contour!(Axis(fig[1, 1]), xs, xs, z, Int64(9), Int64(9))
    contourf!(Axis(fig[1, 2]), xs, xs, z, Int64(9), Int64(9); upsample = 2)
    render!(fig, WasmCtx()); return Int64(0)
end
function w005_mesh()
    fig = Figure(size = (200.0, 150.0))
    ax = Axis(fig[1, 1])
    mesh!(ax, [0.0, 1.0, 0.5], [0.0, 0.0, 1.0], Int64[1, 2, 3];
          color = [:red, :green, :blue])
    render!(fig, WasmCtx()); return Int64(0)
end
function w005_grid()
    fig = Figure(size = (400.0, 300.0))
    lines!(Axis(fig[1, 1]), [0.0, 1.0, 2.0], [0.1, 0.7, 0.4])
    scatter!(Axis(fig[1, 2]), [0.0, 1.0, 2.0], [0.9, 0.2, 0.6])
    barplot!(Axis(fig[2, 1]), [1.0, 2.0, 3.0], [1.0, 2.0, 1.5])
    heatmap!(Axis(fig[2, 2]), [0.0, 1.0, 2.0], [0.0, 1.0],
             [1.0, 2.0], Int64(2), Int64(1))
    render!(fig, WasmCtx()); return Int64(0)
end

@testset "per-plot-type wasm differentials (W-005: scatter, bar, heatmap, image, grid)" begin
    norm(j) = strip(read(`node -e "console.log(JSON.stringify(JSON.parse(process.argv[1])))" $j`, String))
    checker = joinpath(@__DIR__, "wasm_stream_check.js")
    dir = mktempdir()
    glue_path = joinpath(dir, "glue.js"); write(glue_path, js_glue())

    for (name, kernel, size, builder) in [
            ("scatter", w005_scatter, (300.0, 200.0), fig -> begin
                ax = Axis(fig[1, 1])
                scatter!(ax, [0.0, 1.0, 2.0], [0.5, 1.5, 1.0]; markersize = 14.0, color = :red)
                scatter!(ax, [0.5, 1.5], [1.2, 0.8]; marker = :rect, markersize = 10.0)
            end),
            ("bar", w005_bar, (300.0, 200.0),
             fig -> barplot!(Axis(fig[1, 1]), [1.0, 2.0, 3.0], [2.0, -1.0, 3.0]; color = :orange)),
            ("heatmap", w005_heatmap, (300.0, 200.0),
             fig -> heatmap!(Axis(fig[1, 1]), [0.0, 1.0, 2.0, 3.0], [0.0, 1.0, 2.0],
                             [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], Int64(3), Int64(2))),
            ("image", w005_image, (300.0, 200.0), fig -> begin
                px = NTuple{4,Float64}[(1.0, 0.0, 0.0, 1.0), (0.0, 0.0, 1.0, 1.0),
                                       (0.0, 1.0, 0.0, 1.0), (1.0, 1.0, 0.0, 1.0)]
                image!(Axis(fig[1, 1]), (0.0, 2.0), (0.0, 2.0), px, Int64(2), Int64(2);
                       interpolate = false)
            end),
            ("legend", w005_legend, (300.0, 200.0), fig -> begin
                ax = Axis(fig[1, 1])
                lines!(ax, [0.0, 1.0, 2.0], [0.5, 1.5, 1.0]; label = "one")
                scatter!(ax, [0.5, 1.5], [1.2, 0.8]; label = "two", color = :red, markersize = 10.0)
                axislegend(ax)
            end),
            ("colorbar", w005_colorbar, (300.0, 200.0), fig -> begin
                hm = heatmap!(Axis(fig[1, 1]), [0.0, 1.0, 2.0, 3.0], [0.0, 1.0, 2.0],
                              [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], Int64(3), Int64(2))
                Colorbar(fig[1, 2], hm)
            end),
            ("annotations", w005_annotations, (300.0, 200.0), fig -> begin
                ax = Axis(fig[1, 1])
                lines!(ax, [0.0, 1.0, 2.0], [0.5, 1.5, 1.0])
                hlines!(ax, [1.0]; color = :red)
                vlines!(ax, [0.5]; color = :green, linestyle = :dash)
                hspan!(ax, 0.6, 0.8; color = (0.2, 0.4, 0.8, 0.3))
                ablines!(ax, 0.0, 0.7; color = :purple)
                linesegments!(ax, [0.2, 0.8, 1.2, 1.8], [1.4, 1.4, 0.2, 0.2])
            end),
            ("stats", w005_stats, (300.0, 200.0), fig -> begin
                ax = Axis(fig[1, 1])
                stairs!(ax, [0.0, 1.0, 2.0, 3.0], [0.0, 1.0, 0.5, 0.8])
                hist!(ax, [0.1, 0.2, 0.2, 0.3, 0.45, 0.5, 0.5, 0.55, 0.7, 0.9]; bins = 4)
                errorbars!(ax, [0.5, 1.5], [0.5, 0.7], [0.1, 0.2]; color = :red)
                stem!(ax, [2.2, 2.6], [0.4, 0.9])
                density!(ax, [0.1, 0.2, 0.25, 0.3, 0.5, 0.55, 0.6, 0.9])
            end),
            ("composites", w005_composites, (300.0, 200.0), fig -> begin
                ax = Axis(fig[1, 1])
                band!(ax, [0.0, 1.0, 2.0], [0.1, 0.3, 0.2], [0.5, 0.8, 0.6])
                boxplot!(ax, [3.0, 3.0, 3.0, 3.0, 3.0], [0.2, 0.4, 0.5, 0.6, 0.9])
                violin!(ax, [4.0, 4.0, 4.0, 4.0, 4.0], [0.3, 0.4, 0.5, 0.6, 0.7])
                pie!(Axis(fig[1, 2]), [3.0, 2.0, 1.0])
            end),
            ("groupedbars", w005_groupedbars, (300.0, 200.0), fig -> begin
                barplot!(Axis(fig[1, 1]), [1.0, 1.0, 2.0, 2.0], [2.0, 3.0, 1.0, 2.0];
                         dodge = Int64[1, 2, 1, 2])
                barplot!(Axis(fig[1, 2]), [1.0, 1.0, 2.0, 2.0], [2.0, 3.0, 1.0, 2.0];
                         stack = Int64[1, 2, 1, 2])
                waterfall!(Axis(fig[2, 1]), [1.0, 2.0, 3.0], [2.0, -1.0, 3.0])
                crossbar!(Axis(fig[2, 2]), [1.0, 2.0], [2.0, 3.0], [1.0, 2.0], [3.0, 4.0])
            end),
            ("contour", w005_contour, (300.0, 200.0), fig -> begin
                xs = Float64[0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                z = Vector{Float64}(undef, 81)
                for j in 1:9
                    for i in 1:9
                        z[i + (j - 1) * 9] = sin(3.0 * xs[i]) * cos(3.0 * xs[j])
                    end
                end
                contour!(Axis(fig[1, 1]), xs, xs, z, Int64(9), Int64(9))
                contourf!(Axis(fig[1, 2]), xs, xs, z, Int64(9), Int64(9); upsample = 2)
            end),
            ("mesh", w005_mesh, (200.0, 150.0), fig -> begin
                ax = Axis(fig[1, 1])
                mesh!(ax, [0.0, 1.0, 0.5], [0.0, 0.0, 1.0], Int64[1, 2, 3];
                      color = [:red, :green, :blue])
            end),
            ("grid", w005_grid, (400.0, 300.0), fig -> begin
                lines!(Axis(fig[1, 1]), [0.0, 1.0, 2.0], [0.1, 0.7, 0.4])
                scatter!(Axis(fig[1, 2]), [0.0, 1.0, 2.0], [0.9, 0.2, 0.6])
                barplot!(Axis(fig[2, 1]), [1.0, 2.0, 3.0], [1.0, 2.0, 1.5])
                heatmap!(Axis(fig[2, 2]), [0.0, 1.0, 2.0], [0.0, 1.0],
                         [1.0, 2.0], Int64(2), Int64(1))
            end)]
        fig = Figure(size = size)
        builder(fig)
        r = RecordingCtx(); render!(fig, r)
        bytes = compile_with_canvas(Any[(kernel, (), "k")])
        wp = joinpath(dir, name * ".wasm"); write(wp, bytes)
        wasm_json = strip(read(`node $checker $wp $glue_path k`, String))
        @test startswith(wasm_json, "[")
        @test norm(to_json(r)) == norm(wasm_json)
    end
end

@testset "bundled fonts + FontFace loader (T-001)" begin
    # bundled faces exist and FONT_FACES paths resolve
    @test isdir(WasmMakie.FONTS_DIR)
    for (family, weight, style, file) in WasmMakie.FONT_FACES
        @test isfile(joinpath(WasmMakie.FONTS_DIR, file))
    end
    @test isfile(joinpath(WasmMakie.FONTS_DIR, "LICENSES.md"))

    # glue contract: loader + real family names in the fam table
    glue = js_glue()
    @test occursin("canvas2d_load_fonts", glue)
    @test occursin("TeX Gyre Heros Makie", glue)
    @test occursin("DejaVu Sans", glue)

    # local base64 (kept dependency-free) matches the stdlib encoder
    for len in (0, 1, 2, 3, 57, 1000)
        b = UInt8.(mod.(collect(1:len) .* 37, 256))
        @test WasmMakie._base64encode(b) == _B64check.base64encode(b)
    end

    # faces JSON is self-contained (data: URLs) and well-formed
    faces = font_faces_json()
    @test startswith(faces, "[") && occursin("data:font/otf;base64,", faces)
    @test occursin("data:font/ttf;base64,", faces)

    # Chromium proof: fonts actually load and register — page paints the
    # check result into pixel (1,1): green = both families available
    dir = mktempdir()
    html = """
    <!doctype html><html><body>
    <canvas id="c" width="8" height="8"></canvas>
    <script>$(glue)</script>
    <script>
    window.__done = false;
    (async () => {
      try {
        await canvas2d_load_fonts($(faces));
        const ok = document.fonts.check('12px "TeX Gyre Heros Makie"') &&
                   document.fonts.check('italic 700 12px "TeX Gyre Heros Makie"') &&
                   document.fonts.check('12px "DejaVu Sans"');
        const ctx = document.getElementById('c').getContext('2d');
        ctx.fillStyle = ok ? 'rgb(0,255,0)' : 'rgb(255,0,0)';
        ctx.fillRect(0, 0, 8, 8);
        window.__done = true;
      } catch (e) { window.__error = String(e); }
    })();
    </script></body></html>
    """
    html_path = joinpath(dir, "fontcheck.html"); write(html_path, html)
    png_path = joinpath(dir, "out.png")
    script = joinpath(dirname(@__DIR__), "assets", "render_page.mjs")
    out = IOBuffer()
    proc = run(pipeline(ignorestatus(`node $script $html_path $png_path "[[1,1]]"`); stdout = out))
    if proc.exitcode == 2
        @test_skip "playwright unavailable"
    else
        @test proc.exitcode == 0
        @test occursin("PROBE 1,1 = 0,255,0,255", String(take!(out)))
    end

    # loaded fonts change real text metrics vs generic sans-serif (the whole
    # point of T-001) — render the same string via the replay page and probe
    # for ink inside the glyph box
    rctx = RecordingCtx()
    WasmMakie.set_fill_rgba(rctx, 255.0, 255.0, 255.0, 1.0)
    WasmMakie.fill_rect(rctx, 0.0, 0.0, 120.0, 60.0)
    WasmMakie.set_fill_rgba(rctx, 0.0, 0.0, 0.0, 1.0)
    WasmMakie.set_font(rctx, Int64(0), 40.0, Int64(400), Int64(0))
    WasmMakie.text_buf_clear(rctx)
    for c in "MM"
        WasmMakie.text_buf_push(rctx, Int64(codepoint(c)))
    end
    WasmMakie.fill_text_buf(rctx, 10.0, 45.0)
    res = render_commands(to_json(rctx); width = 120, height = 60,
                          probes = [(3, 3)])
    if res === nothing
        @test_skip "playwright unavailable"
    else
        @test res.pixels[(3, 3)] == (255, 255, 255, 255)  # background untouched
        # decode the PNG row sweep is overkill — ink presence via probe grid
        inked = false
        res2 = render_commands(to_json(rctx); width = 120, height = 60,
                               probes = [(x, y) for x in 12:6:60 for y in 18:6:42])
        for (_, px) in res2.pixels
            px[1] < 200 && (inked = true)
        end
        @test inked
    end
end

# T-002 wasm kernels (top-level: closures don't compile)
function k_t002_cache()
    p = ExtentProvider()
    ctx = WasmCtx()
    g1 = glyph_extent!(p, ctx, Int64(77), Int64(0), Int64(400), Int64(0))
    g2 = glyph_extent!(p, ctx, Int64(77), Int64(0), Int64(400), Int64(0))
    g3 = glyph_extent!(p, ctx, Int64(77), Int64(0), Int64(400), Int64(0))
    return Int64(length(p.keys)) + Int64(round(1000.0 * (g1.hadvance + g2.hadvance + g3.hadvance)))
end

function k_t002_draw_measured()
    ctx = WasmCtx()
    WasmMakie.set_fill_rgba(ctx, 255.0, 255.0, 255.0, 1.0)
    WasmMakie.fill_rect(ctx, 0.0, 0.0, 120.0, 30.0)
    p = ExtentProvider()
    g = glyph_extent!(p, ctx, Int64(77), Int64(0), Int64(400), Int64(0))  # 'M'
    WasmMakie.set_fill_rgba(ctx, 255.0, 0.0, 0.0, 1.0)
    WasmMakie.fill_rect(ctx, 0.0, 0.0, g.hadvance * 64.0, 10.0)
    return Int64(0)
end

@testset "measure_text extent provider (T-002)" begin
    # RecordingCtx oracle: extents reflect the deterministic stand-in ratios,
    # normalized per font-size unit
    r = RecordingCtx()
    p = ExtentProvider()
    g = glyph_extent!(p, r, Int64(77), Int64(0), Int64(400), Int64(0))
    @test g.hadvance ≈ 0.55
    @test g.ascent ≈ 0.8
    @test g.descent ≈ 0.2
    @test g.left ≈ 0.04
    @test g.right ≈ 0.51
    # one miss = set_font + clear + push + 7 measures = 10 ops
    @test length(r.commands) == 10

    # cache hit: no new ops, identical object semantics
    g2 = glyph_extent!(p, r, Int64(77), Int64(0), Int64(400), Int64(0))
    @test length(r.commands) == 10
    @test g2.hadvance == g.hadvance
    # different face = new entry
    glyph_extent!(p, r, Int64(77), Int64(0), Int64(700), Int64(0))
    @test length(p.keys) == 2
    @test length(r.commands) == 20

    # key packing is collision-free across the fields
    ks = [WasmMakie._extent_key(cp, fam, wt, it)
          for cp in Int64[65, 0x10FFFF], fam in Int64[0, 2],
              wt in Int64[400, 700], it in Int64[0, 1]]
    @test allunique(ks)

    # derived helpers
    cps = Int64[72, 105]  # "Hi"
    adv = text_advance!(p, r, cps, 14.0, Int64(0), Int64(400), Int64(0))
    @test adv ≈ 2 * 0.55 * 14.0
    w, asc, desc = string_extent!(p, r, cps, 14.0, Int64(0), Int64(400), Int64(0))
    @test w ≈ adv && asc ≈ 0.8 * 14.0 && desc ≈ 0.2 * 14.0

    # compiled: the cache works in wasm — 3 lookups, ONE measure group in the
    # logged stream (stream-checker measureText returns 0s; cache size is 1)
    bytes = compile_with_canvas(Any[(k_t002_cache, (), "k")])
    dir = mktempdir()
    wp = joinpath(dir, "k.wasm"); write(wp, bytes)
    gp = joinpath(dir, "glue.js"); write(gp, js_glue())
    checker = joinpath(@__DIR__, "wasm_stream_check.js")
    stream_json = strip(read(`node $checker $wp $gp k`, String))
    @test startswith(stream_json, "[")
    counts = read(`node -e "
      const s = JSON.parse(process.argv[1]);
      const n = (op) => s.filter(c => c.op === op).length;
      console.log(n('set_font'), n('measure_text_buf_width'), n('measure_text_buf_left'));
    " $stream_json`, String)
    @test strip(counts) == "1 1 1"

    # browser: a LIVE measureText value (loaded TeX Gyre face) flows through
    # the typed provider in wasm — red rect width == measured 'M' advance @64px
    bytes2 = compile_with_canvas(Any[(k_t002_draw_measured, (), "k")])
    res = render_wasm(bytes2, "k"; width = 120, height = 30,
                      probes = [(10, 2), (40, 2), (60, 2), (110, 2)])
    if res === nothing
        @test_skip "playwright unavailable"
    else
        @test res.pixels[(10, 2)] == (255, 0, 0, 255)   # inside any plausible M
        @test res.pixels[(40, 2)] == (255, 0, 0, 255)   # M advance ≥ ~45px @64
        @test res.pixels[(60, 2)] == (255, 255, 255, 255) # and ≤ ~58px
        @test res.pixels[(110, 2)] == (255, 255, 255, 255)
    end
end

# T-003 wasm kernel (top-level: closures don't compile)
function k_t003_layout()
    p = ExtentProvider()
    ctx = WasmCtx()
    cps = Int64[72, 105, 10, 87, 111, 114, 108, 100]  # "Hi\nWorld"
    gc = glyph_collection!(p, ctx, cps, Int64(0), Int64(400), Int64(0),
                           14.0, 0.5, -1.0, 1.0, -1.0, 0.0, 0.0)
    return Int64(length(gc.glyphs))
end

@testset "vendored text layouting (T-003)" begin
    # oracles below are hand-derived from the RecordingCtx stand-in ratios:
    # advance 0.55/unit, font ascent 0.9/unit, font descent 0.25/unit
    # → at scale 10: adv 5.5, ascender 9.0, descender −2.5, lineheight 11.5
    r = RecordingCtx()
    p = ExtentProvider()
    s = 10.0

    # alignment resolution mirrors upstream halign2num/valign2num
    @test halign2num(:left) == 0.0 && halign2num(:center) == 0.5 && halign2num(:right) == 1.0
    @test valign2num(:top) == 1.0 && valign2num(:bottom) == 0.0 && valign2num(:baseline) == -1.0
    @test halign2num(0.25) == 0.25

    # single line, left/baseline: origins on the baseline anchor
    gc = glyph_collection!(p, r, Int64[72, 105], Int64(0), Int64(400), Int64(0),
                           s, 0.0, -1.0, 1.0, -1.0, 0.0, 0.0)
    @test gc.glyphs == [72, 105]
    @test gc.origins_x ≈ [0.0, 5.5]
    @test gc.origins_y ≈ [0.0, 0.0]

    # right/bottom: shifted left by maxwidth, baseline raised by descender
    gc = glyph_collection!(p, r, Int64[72, 105], Int64(0), Int64(400), Int64(0),
                           s, 1.0, 0.0, 1.0, -1.0, 0.0, 0.0)
    @test gc.origins_x ≈ [-11.0, -5.5]
    @test gc.origins_y ≈ [2.5, 2.5]

    # two lines "A\nB", left/top: second baseline one lineheight down
    gc = glyph_collection!(p, r, Int64[65, 10, 66], Int64(0), Int64(400), Int64(0),
                           s, 0.0, 1.0, 1.0, -1.0, 0.0, 0.0)
    @test gc.glyphs == [65, 10, 66]
    @test gc.origins_x ≈ [0.0, 5.5, 0.0]
    @test gc.origins_y ≈ [-9.0, -9.0, -20.5]

    # empty string
    gc0 = glyph_collection!(p, r, Int64[], Int64(0), Int64(400), Int64(0),
                            s, 0.0, -1.0, 1.0, -1.0, 0.0, 0.0)
    @test isempty(gc0.glyphs) && isempty(gc0.origins_x)

    # rotation π/2 about the anchor: (x, y) → (−y, x)
    gcr = glyph_collection!(p, r, Int64[72, 105], Int64(0), Int64(400), Int64(0),
                            s, 0.0, -1.0, 1.0, -1.0, pi / 2, 0.0)
    @test gcr.origins_x ≈ [0.0, 0.0] atol = 1e-12
    @test gcr.origins_y ≈ [0.0, 5.5]

    # justification: two-line right-justified, left-aligned block
    gcj = glyph_collection!(p, r, Int64[65, 66, 10, 67], Int64(0), Int64(400), Int64(0),
                            s, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0)
    # line widths 11 ("AB") and 5.5 ("C"); C shifted right by 5.5
    @test gcj.origins_x ≈ [0.0, 5.5, 11.0, 5.5]

    # word wrap: "AB CD" at width 15 breaks the space into a newline
    gcw = glyph_collection!(p, r, Int64[65, 66, 32, 67, 68], Int64(0), Int64(400), Int64(0),
                            s, 0.0, 1.0, 1.0, -1.0, 0.0, 15.0)
    @test gcw.glyphs == [65, 66, 10, 67, 68]   # space rewritten to \n
    @test gcw.origins_x ≈ [0.0, 5.5, 11.0, 0.0, 5.5]
    @test gcw.origins_y[4] ≈ gcw.origins_y[1] - 11.5

    # compiled: the full layouting runs in wasm (8 distinct glyphs = 8 cache
    # misses in the logged stream; no trap)
    bytes = compile_with_canvas(Any[(k_t003_layout, (), "k")])
    dir = mktempdir()
    wp = joinpath(dir, "k.wasm"); write(wp, bytes)
    gp = joinpath(dir, "glue.js"); write(gp, js_glue())
    checker = joinpath(@__DIR__, "wasm_stream_check.js")
    stream_json = strip(read(`node $checker $wp $gp k`, String))
    @test startswith(stream_json, "[")
    counts = read(`node -e "
      const s = JSON.parse(process.argv[1]);
      console.log(s.filter(c => c.op === 'set_font').length);
    " $stream_json`, String)
    @test strip(counts) == "8"
end

# T-004 wasm kernel: deterministic-table layout, pure compute (no imports)
function k_t004_table_layout()
    t = TableExtents()
    ctx = WasmCtx()
    # "−1.5×10\nHi" — mixed charset incl. the non-ASCII tick glyphs
    cps = Int64[0x2212, 49, 46, 53, 0x00D7, 49, 48, 10, 72, 105]
    gc = glyph_collection!(t, ctx, cps, Int64(0), Int64(400), Int64(0),
                           14.0, 0.5, 1.0, 1.0, -1.0, 0.3, 0.0)
    s = 0.0
    for i in eachindex(gc.origins_x)
        s += gc.origins_x[i] * Float64(i) + gc.origins_y[i]
    end
    return Int64(round(1.0e6 * s))
end

@testset "deterministic metric tables (T-004)" begin
    # table shape + face-level values straight from FreeType
    @test length(WasmMakie.GLYPH_METRICS) == 5 * WasmMakie.METRIC_NCPS
    @test length(WasmMakie.FACE_METRICS) == 5
    @test WasmMakie.FACE_METRICS[1] == (0.947, 0.218, 1.165)  # TGH (= axis TEXT_HEIGHT_RATIO)

    t = TableExtents()
    r = RecordingCtx()
    # 'M' in TGH Regular: Helvetica-metric advance, no ctx traffic
    gM = glyph_extent!(t, r, Int64(77), Int64(0), Int64(400), Int64(0))
    @test gM.hadvance ≈ 0.833
    @test isempty(r.commands)   # tables are pure — no measure ops recorded
    @test gM.font_height ≈ 1.165

    # tabular figures: all ten digits share one advance (tick alignment)
    d0 = glyph_extent!(t, r, Int64('0'), Int64(0), Int64(400), Int64(0)).hadvance
    for c in '1':'9'
        @test glyph_extent!(t, r, Int64(c), Int64(0), Int64(400), Int64(0)).hadvance == d0
    end

    # bold face differs from regular (block-level: M advance is identical in
    # Helvetica metrics, but ink bounds differ), DejaVu fam differs
    n97 = WasmMakie.METRIC_NCPS
    @test WasmMakie.GLYPH_METRICS[1:n97] != WasmMakie.GLYPH_METRICS[(n97 + 1):(2n97)]
    gMb = glyph_extent!(t, r, Int64(77), Int64(0), Int64(700), Int64(0))
    @test (gMb.left, gMb.right) != (gM.left, gM.right)
    gMd = glyph_extent!(t, r, Int64(77), Int64(1), Int64(400), Int64(0))
    @test gMd.hadvance != gM.hadvance
    gq = glyph_extent!(t, r, Int64(0x4E2D), Int64(0), Int64(400), Int64(0))
    @test gq.hadvance == glyph_extent!(t, r, Int64('?'), Int64(0), Int64(400), Int64(0)).hadvance

    # the tick-label glyphs are real entries (− and ×), not fallbacks
    gminus = glyph_extent!(t, r, Int64(0x2212), Int64(0), Int64(400), Int64(0))
    @test gminus.hadvance > 0.3 && gminus.hadvance != gq.hadvance

    # THE T-004 GATE: table-driven layout is BIT-IDENTICAL native vs wasm
    native = k_t004_table_layout()
    @test native != 0
    bytes = compile_with_canvas(Any[(k_t004_table_layout, (), "k")])
    dir = mktempdir()
    wp = joinpath(dir, "k.wasm"); write(wp, bytes)
    runner = joinpath(dir, "run.js")
    write(runner, """
    const fs = require('fs');
    WebAssembly.instantiate(fs.readFileSync(process.argv[2]),
        {canvas2d: new Proxy({}, {get: () => () => 0n}), Math: {pow: Math.pow}}).then(m => {
      console.log('RESULT ' + m.instance.exports.k());
    }).catch(e => console.log('FAIL ' + e));
    """)
    out = strip(read(`node $runner $wp`, String))
    @test out == "RESULT $native"

    # browser cross-check: the table predicts REAL rendered ink — 'H' at 64px,
    # probe the crossbar center the TABLE computes
    rr = RecordingCtx()
    WasmMakie.set_fill_rgba(rr, 255.0, 255.0, 255.0, 1.0)
    WasmMakie.fill_rect(rr, 0.0, 0.0, 120.0, 80.0)
    WasmMakie.set_fill_rgba(rr, 0.0, 0.0, 0.0, 1.0)
    WasmMakie.set_font(rr, Int64(0), 64.0, Int64(400), Int64(0))
    WasmMakie.text_buf_clear(rr)
    WasmMakie.text_buf_push(rr, Int64('H'))
    WasmMakie.fill_text_buf(rr, 10.0, 70.0)
    gH = glyph_extent!(t, rr, Int64('H'), Int64(0), Int64(400), Int64(0))
    px = 10 + round(Int, 0.5 * (gH.right - gH.left) * 64)   # ink center x (left is −leftinkbound)
    py = 70 - round(Int, 0.5 * gH.ascent * 64)              # crossbar y
    res = render_commands(to_json(rr); width = 120, height = 80,
                          probes = [(px, py), (110, 10)])
    if res === nothing
        @test_skip "playwright unavailable"
    else
        @test res.pixels[(px, py)][1] < 128       # crossbar ink where the table says
        @test res.pixels[(110, 10)] == (255, 255, 255, 255)
    end
end

@testset "vendored optimize_ticks sanity (C-002)" begin
    ticks, lo, hi = WasmMakie.optimize_ticks(0.0, 10.0)
    @test ticks == [0.0, 5.0, 10.0]
    @test lo == 0.0 && hi == 10.0
    ticks2, _, _ = WasmMakie.optimize_ticks(0.0, 1.0)
    @test first(ticks2) >= 0.0 && last(ticks2) <= 1.0
    @test length(ticks2) >= 2
    # degenerate span falls back
    t3, _, _ = WasmMakie.optimize_ticks(5.0, 5.0 + 1.0e-13)
    @test length(t3) == 2
end

@testset "WasmMakie scaffold" begin
    @test WasmMakie isa Module
    @test pkgversion(WasmMakie) == v"0.0.1"
    # Host-agnostic guarantee: no web-framework or notebook-system reference
    # may ever appear in src/. This test is the enforcement.
    src_dir = joinpath(dirname(@__DIR__), "src")
    banned = ["Therapy", "Pluto", "Sessions.jl", "PlutoIslands"]
    for (root, _, files) in walkdir(src_dir), f in files
        endswith(f, ".jl") || continue
        content = read(joinpath(root, f), String)
        for word in banned
            @test !occursin(word, content)
        end
    end
end

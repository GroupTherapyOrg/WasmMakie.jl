using Test
using WasmMakie
import WasmTarget

@testset "ops table (F-002)" begin
    ops = WasmMakie.CANVAS_OPS
    @test length(ops) == 61
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
    @test occursin("JS GLUE OK: 61 ops", out)
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
    @test strip(nops) == "61"

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
    @test ax.titlesize == 16.0 && ax.xlabelsize == 14.0

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
    oracle = readlines(`julia +1.12 --project=$proj -e $script`)
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

    # barplot!: defaults from Makie (gap 0.2), limits reach to 0
    b1 = barplot!(ax, [1, 2], [3.0, -1.0]; color = (0.0, 0.0, 1.0, 1.0))
    @test b1.gap == 0.2
    @test WasmMakie.data_limits(b1) == (1.0, 2.0, -1.0, 3.0)

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

    # protrusions: approximate parity vs Makie oracle (default axis:
    # left 16.784, bottom 23.31) — exact extents arrive with T-004
    res2 = WasmMakie.resolve_axis(ax2)
    # sanity bands only — Makie composes these from real FreeType extents
    # (oracle: bottom 23.31, left 16.784); exact parity is T-004-gated
    @test 18.0 < res2.prot.b < 28.0
    @test 10.0 < res2.prot.l < 30.0
    @test res2.prot.t == 0.0 && res2.prot.r == 0.0
    # labels/title add protrusion
    ax4 = Axis(Figure()[1, 1]; title = "T", xlabel = "x", ylabel = "y")
    res4 = WasmMakie.resolve_axis(ax4)
    @test res4.prot.b > res2.prot.b
    @test res4.prot.l > res2.prot.l
    @test res4.prot.t > 0.0
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

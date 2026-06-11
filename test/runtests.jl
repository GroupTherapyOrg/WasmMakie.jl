using Test
using WasmMakie

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

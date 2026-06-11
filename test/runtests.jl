using Test
using WasmMakie

@testset "ops table (F-002)" begin
    ops = WasmMakie.CANVAS_OPS
    @test length(ops) == 58
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
    @test occursin("JS GLUE OK: 58 ops", out)
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

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

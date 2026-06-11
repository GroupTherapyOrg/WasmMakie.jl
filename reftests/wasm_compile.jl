# WasmTarget compile glue — turns WasmMakie-drawing Julia functions into wasm
# modules with the canvas2d import surface registered from the ops table.
#
# This is the seed of the embedding contract's compile path (plan E-001): the
# import wiring below is exactly what any host does — every spec row becomes a
# wasm import, every `canvas_*` stub call in compiled code becomes a call to
# that import.
module WasmCompile

using WasmMakie
import WasmTarget as WT

export compile_with_canvas

"""
    compile_with_canvas(functions) -> Vector{UInt8}

Compile `[(func, arg_types, export_name), ...]` to a wasm module with all 58
canvas2d imports registered. Strict mode, validated by WasmTarget's pipeline.
"""
function compile_with_canvas(functions::Vector)
    mod = WT.WasmModule()
    # Math.pow import matches WasmTarget's default module setup
    WT.add_import!(mod, "Math", "pow", WT.NumType[WT.F64, WT.F64], WT.NumType[WT.F64])

    import_stubs = Any[]
    for s in WasmMakie.import_specs()
        params = WT.NumType[p === :F64 ? WT.F64 : WT.I64 for p in s.params]
        ret = WT.NumType[s.ret === :F64 ? WT.F64 : WT.I64]
        idx = WT.add_import!(mod, s.mod, s.name, params, ret)
        push!(import_stubs, (s.func, s.name, Tuple(s.arg_types), idx, s.return_type))
    end

    wmod = WT.compile_module(functions; existing_module = mod, import_stubs = import_stubs)
    return WT.to_bytes(wmod)
end

end # module

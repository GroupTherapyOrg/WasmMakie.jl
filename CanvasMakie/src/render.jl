# Pixels for the backend: a recorded command stream renders on a real canvas
# in headless Chromium (WasmMakie's replay.js + render_page.mjs, resolved from
# the WasmMakie package dir). This is the backend's rasterizer — the same JS
# path a live wasm module uses in production.

struct RendererUnavailable <: Exception end
Base.showerror(io::IO, ::RendererUnavailable) =
    print(io, "CanvasMakie: headless Chromium renderer unavailable (playwright not found)")

struct RenderError <: Exception
    msg::String
end
Base.showerror(io::IO, e::RenderError) = print(io, "CanvasMakie render error: ", e.msg)

const _WASMMAKIE_DIR = pkgdir(WasmMakie)

function _page_html(commands_json, specs_json, glue, replay_src; width, height)
    return """
    <!doctype html><html><body>
    <canvas id="c" width="$(width)" height="$(height)"></canvas>
    <script>$(glue)</script>
    <script>$(replay_src)</script>
    <script>
    window.__done = false;
    (async () => {
      try {
        await canvas2d_load_fonts($(WasmMakie.font_faces_json()));
        const canvas = document.getElementById('c');
        replayCommands($(commands_json), canvas, canvas2d_imports, $(specs_json));
        window.__done = true;
      } catch (e) { window.__error = String(e); }
    })();
    </script></body></html>
    """
end

"""
    commands_to_png(rctx::WasmMakie.RecordingCtx, width, height) -> Vector{UInt8}

Render a recorded command stream to PNG bytes via headless Chromium.
Throws `RendererUnavailable` (no playwright) or `RenderError` (page failure).
"""
function commands_to_png(rctx::WasmMakie.RecordingCtx, width::Int, height::Int)
    glue = WasmMakie.js_glue()
    specs = WasmMakie.js_specs()
    replay_src = read(joinpath(_WASMMAKIE_DIR, "assets", "replay.js"), String)
    dir = mktempdir()
    html_path = joinpath(dir, "page.html")
    write(html_path, _page_html(WasmMakie.to_json(rctx), specs, glue, replay_src; width, height))
    png_path = joinpath(dir, "out.png")
    script = joinpath(_WASMMAKIE_DIR, "assets", "render_page.mjs")

    out = IOBuffer(); err = IOBuffer()
    proc = run(pipeline(ignorestatus(`node $script $html_path $png_path "[]"`);
                        stdout = out, stderr = err))
    proc.exitcode == 2 && throw(RendererUnavailable())
    sout = String(take!(out)); serr = String(take!(err))
    proc.exitcode == 0 || throw(RenderError(strip(serr * "\n" * sout)))
    return read(png_path)
end

"""
    renderer_available() -> Bool

True when the headless Chromium renderer can run (used by test suites to skip).
"""
function renderer_available()
    rctx = WasmMakie.RecordingCtx()
    WasmMakie.fill_rect(rctx, 0.0, 0.0, 1.0, 1.0)
    try
        commands_to_png(rctx, 2, 2)
        return true
    catch e
        e isa RendererUnavailable && return false
        rethrow()
    end
end

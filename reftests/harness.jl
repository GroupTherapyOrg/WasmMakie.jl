# Headless render harness — turns a WasmMakie command stream into real pixels.
#
# `render_commands(json)` builds a self-contained HTML page (generated glue +
# replay.js + the command stream), renders it in headless Chromium via
# render_page.mjs, and returns the canvas PNG bytes plus any requested pixel
# probes. Returns `nothing` when playwright is unavailable (callers skip).
#
# This is deliberately NOT part of the WasmMakie package — it is test/oracle
# tooling, included by the test suites that need pixels.
module Harness

using WasmMakie
import Base64

export render_commands, render_wasm, png_dims, PageError

const REFTESTS_DIR = @__DIR__
const PKG_DIR = dirname(REFTESTS_DIR)

struct PageError <: Exception
    msg::String
end
Base.showerror(io::IO, e::PageError) = print(io, "PageError: ", e.msg)

function _page_html(commands_json, specs_json, glue, replay_src; width, height)
    return """
    <!doctype html><html><body>
    <canvas id="c" width="$(width)" height="$(height)"></canvas>
    <script>$(glue)</script>
    <script>$(replay_src)</script>
    <script>
    window.__done = false;
    try {
      const canvas = document.getElementById('c');
      replayCommands($(commands_json), canvas, canvas2d_imports, $(specs_json));
      window.__done = true;
    } catch (e) { window.__error = String(e); }
    </script></body></html>
    """
end

"""
    render_commands(commands_json; width=640, height=480, probes=Tuple{Int,Int}[])

Render a serialized command stream on a real canvas in headless Chromium.
Returns `(png = Vector{UInt8}, pixels = Dict{(x,y) => (r,g,b,a)})`, or
`nothing` if playwright is unavailable. Throws `PageError` if the stream
fails to replay in the page.
"""
function render_commands(commands_json::AbstractString;
                         width::Int = 640, height::Int = 480,
                         probes::Vector{Tuple{Int,Int}} = Tuple{Int,Int}[])
    glue = WasmMakie.js_glue()
    specs = WasmMakie.js_specs()
    replay_src = read(joinpath(PKG_DIR, "assets", "replay.js"), String)
    dir = mktempdir()
    html_path = joinpath(dir, "page.html")
    write(html_path, _page_html(commands_json, specs, glue, replay_src; width, height))
    png_path = joinpath(dir, "out.png")
    probes_json = "[" * join(["[$x,$y]" for (x, y) in probes], ",") * "]"
    script = joinpath(REFTESTS_DIR, "render_page.mjs")

    out = IOBuffer(); err = IOBuffer()
    proc = run(pipeline(ignorestatus(`node $script $html_path $png_path $probes_json`);
                        stdout = out, stderr = err))
    proc.exitcode == 2 && return nothing  # playwright unavailable
    sout = String(take!(out)); serr = String(take!(err))
    proc.exitcode == 0 || throw(PageError(strip(serr * "\n" * sout)))
    occursin("DONE", sout) || throw(PageError("renderer produced no DONE marker:\n" * sout))

    pixels = Dict{Tuple{Int,Int},NTuple{4,Int}}()
    for line in split(sout, '\n')
        m = match(r"^PROBE (\d+),(\d+) = (\d+),(\d+),(\d+),(\d+)$", line)
        m === nothing && continue
        pixels[(parse(Int, m[1]), parse(Int, m[2]))] =
            (parse(Int, m[3]), parse(Int, m[4]), parse(Int, m[5]), parse(Int, m[6]))
    end
    return (png = read(png_path), pixels = pixels)
end

function _wasm_page_html(wasm_b64, glue, export_name; width, height)
    return """
    <!doctype html><html><body>
    <canvas id="c" width="$(width)" height="$(height)"></canvas>
    <script>$(glue)</script>
    <script>
    window.__done = false;
    (async () => {
      try {
        const bytes = Uint8Array.from(atob('$(wasm_b64)'), (ch) => ch.charCodeAt(0));
        const canvas = document.getElementById('c');
        const imports = { canvas2d: canvas2d_imports(canvas), Math: { pow: Math.pow } };
        const { instance } = await WebAssembly.instantiate(bytes, imports);
        window.__result = instance.exports.$(export_name)();
        window.__done = true;
      } catch (e) { window.__error = String(e); }
    })();
    </script></body></html>
    """
end

"""
    render_wasm(wasm_bytes, export_name; width=640, height=480, probes=[])

Instantiate a compiled wasm module against a real canvas in headless Chromium,
call the named export, and return `(png, pixels)` like `render_commands`.
Returns `nothing` when playwright is unavailable.
"""
function render_wasm(wasm_bytes::Vector{UInt8}, export_name::AbstractString;
                     width::Int = 640, height::Int = 480,
                     probes::Vector{Tuple{Int,Int}} = Tuple{Int,Int}[])
    glue = WasmMakie.js_glue()
    wasm_b64 = Base64.base64encode(wasm_bytes)
    dir = mktempdir()
    html_path = joinpath(dir, "page.html")
    write(html_path, _wasm_page_html(wasm_b64, glue, export_name; width, height))
    png_path = joinpath(dir, "out.png")
    probes_json = "[" * join(["[$x,$y]" for (x, y) in probes], ",") * "]"
    script = joinpath(REFTESTS_DIR, "render_page.mjs")

    out = IOBuffer(); err = IOBuffer()
    proc = run(pipeline(ignorestatus(`node $script $html_path $png_path $probes_json`);
                        stdout = out, stderr = err))
    proc.exitcode == 2 && return nothing
    sout = String(take!(out)); serr = String(take!(err))
    proc.exitcode == 0 || throw(PageError(strip(serr * "\n" * sout)))

    pixels = Dict{Tuple{Int,Int},NTuple{4,Int}}()
    for line in split(sout, '\n')
        m = match(r"^PROBE (\d+),(\d+) = (\d+),(\d+),(\d+),(\d+)$", line)
        m === nothing && continue
        pixels[(parse(Int, m[1]), parse(Int, m[2]))] =
            (parse(Int, m[3]), parse(Int, m[4]), parse(Int, m[5]), parse(Int, m[6]))
    end
    return (png = read(png_path), pixels = pixels)
end

"""
    png_dims(bytes) -> (width, height)

Parse a PNG's dimensions straight from its IHDR chunk (no image deps).
"""
function png_dims(bytes::Vector{UInt8})
    @assert bytes[1:8] == UInt8[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] "not a PNG"
    w = (Int(bytes[17]) << 24) | (Int(bytes[18]) << 16) | (Int(bytes[19]) << 8) | Int(bytes[20])
    h = (Int(bytes[21]) << 24) | (Int(bytes[22]) << 16) | (Int(bytes[23]) << 8) | Int(bytes[24])
    return (w, h)
end

end # module

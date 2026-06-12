// Command-stream replayer.
//
// Replays a serialized WasmMakie command stream (the JSON produced by
// Julia-side `to_json(::RecordingCtx)`) onto a real canvas by calling the
// SAME generated glue the wasm module uses — so a replayed host-side
// recording and a live wasm run exercise identical JS code paths.
//
//   replayCommands(commands, target, importsFactory, specs)
//     commands       — parsed JSON array of {op, args}
//     target         — <canvas> element or 2d context
//     importsFactory — the generated `canvas2d_imports` function (js_glue())
//     specs          — parsed JSON from js_specs(); maps op → param kinds,
//                      used to convert I64 args to BigInt
//
// Works in node (module.exports) and the browser (globalThis.replayCommands).
(function (global) {
  function replayCommands(commands, target, importsFactory, specs) {
    const imports = importsFactory(target);
    const b64decode = (s) =>
      typeof Buffer !== 'undefined' ? Uint8Array.from(Buffer.from(s, 'base64'))
                                    : Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
    for (const cmd of commands) {
      // synthetic op from to_json: a coalesced run of img_buf_push_rgba
      // pixels as base64 RGBA bytes — expanded through the SAME glue call
      if (cmd.op === 'img_buf_push_rgba_b64') {
        const bytes = b64decode(cmd.args[0]);
        for (let k = 0; k < bytes.length; k += 4) {
          imports.img_buf_push_rgba(BigInt(bytes[k]), BigInt(bytes[k + 1]),
                                    BigInt(bytes[k + 2]), BigInt(bytes[k + 3]));
        }
        continue;
      }
      const kinds = specs[cmd.op];
      if (!kinds) throw new Error('replay: unknown op "' + cmd.op + '"');
      if (kinds.length !== cmd.args.length) {
        throw new Error('replay: arity mismatch for "' + cmd.op + '": expected ' +
          kinds.length + ', got ' + cmd.args.length);
      }
      const args = cmd.args.map((a, i) => (kinds[i] === 'I64' ? BigInt(a) : a));
      imports[cmd.op](...args);
    }
    return commands.length;
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = { replayCommands };
  else global.replayCommands = replayCommands;
})(typeof globalThis !== 'undefined' ? globalThis : this);

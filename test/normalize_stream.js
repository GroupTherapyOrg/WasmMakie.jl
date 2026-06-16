// Canonicalize a recorded canvas command stream for the wasm differential.
//
// to_json coalesces runs of >= 8 img_buf_push_rgba commands into one
// synthetic img_buf_push_rgba_b64 op (see src/ctx.jl); the wasm side calls the
// per-pixel import directly and so records raw img_buf_push_rgba ops. Expand
// the coalesced op back to per-pixel ops so both streams compare at the same
// level, then re-stringify (which also normalizes number formatting).
//
// Usage: node normalize_stream.js <stream.json>   (reads the stream from a
// file, not argv, because image streams exceed the platform argv size cap).
const fs = require('fs');
const cmds = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const out = [];
for (const c of cmds) {
  if (c.op === 'img_buf_push_rgba_b64') {
    const b = Buffer.from(c.args[0], 'base64');
    for (let k = 0; k < b.length; k += 4) {
      out.push({ op: 'img_buf_push_rgba', args: [b[k], b[k + 1], b[k + 2], b[k + 3]] });
    }
  } else {
    out.push(c);
  }
}
console.log(JSON.stringify(out));

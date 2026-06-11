// Round-trip check: Julia RecordingCtx → to_json → replayCommands → real glue
// → logging ctx. Asserts the exact canvas calls the stream must produce,
// including I64→BigInt reconversion, dash slicing, font assembly, buffered
// text, buffered images, and the gradient handle model.
// Usage: node replay_check.js <glue.js> <replay.js> <specs.json> <commands.json>
const fs = require('fs');
const [, , gluePath, replayPath, specsPath, commandsPath] = process.argv;
const glueSrc = fs.readFileSync(gluePath, 'utf8');
const { replayCommands } = require(fs.realpathSync(replayPath));
const specs = JSON.parse(fs.readFileSync(specsPath, 'utf8'));
const commands = JSON.parse(fs.readFileSync(commandsPath, 'utf8'));

globalThis.ImageData = class { constructor(data, w, h) { this.data = data; this.width = w; this.height = h; } };

const log = [];
const grad = { addColorStop: (o, c) => log.push(['addColorStop', o, c]) };
const ctxState = {};
const loggingCtx = new Proxy({}, {
  get(t, prop) {
    if (prop === 'getContext') return undefined; // we ARE the ctx
    if (prop === 'measureText') return () => ({ width: 42, actualBoundingBoxAscent: 8, actualBoundingBoxDescent: 2 });
    if (prop === 'canvas') return { width: 640, height: 480 };
    if (prop === 'createLinearGradient') return (...a) => { log.push(['createLinearGradient', ...a]); return grad; };
    if (prop in ctxState) return ctxState[prop];
    return (...a) => { log.push([prop, ...a]); };
  },
  set(t, prop, v) { ctxState[prop] = v; log.push(['set:' + prop, (typeof v === 'object') ? '<obj>' : v]); return true; },
});
globalThis.OffscreenCanvas = class { constructor(w, h) { } getContext() { return loggingCtx; } };

const factory = new Function(glueSrc + '\nreturn canvas2d_imports;')();
const n = replayCommands(commands, loggingCtx, factory, specs);

let failures = 0;
const expect = (desc, pred) => {
  if (!pred) { console.error('FAIL: ' + desc); failures++; }
};
const find = (head) => log.filter((e) => e[0] === head);

expect('replayed all commands', n === commands.length);
expect('beginPath called', find('beginPath').length === 1);
expect('moveTo(1, 2)', find('moveTo').some((e) => e[1] === 1 && e[2] === 2));
expect('arc ccw flag reconverted to boolean true', find('arc').some((e) => e[6] === true));
expect('setLineDash sliced to [6, 4]', find('setLineDash').some((e) => JSON.stringify(e[1]) === '[6,4]'));
expect("font assembled as '400 12px sans-serif'", ctxState.font === '400 12px sans-serif');
expect("fillText('Hi', 10, 20) from buffered codepoints",
  find('fillText').some((e) => e[1] === 'Hi' && e[2] === 10 && e[3] === 20));
expect("lineCap set to 'round'", ctxState.lineCap === 'round');
const pid = find('putImageData');
expect('putImageData received 2x1 ImageData', pid.length === 1 && pid[0][1].width === 2 && pid[0][1].height === 1);
expect('image bytes in order', pid.length === 1 &&
  JSON.stringify(Array.from(pid[0][1].data)) === '[10,20,30,255,40,50,60,255]');
expect('createLinearGradient called', find('createLinearGradient').length === 1);
expect('addColorStop with rgba string', find('addColorStop').some((e) => String(e[2]).startsWith('rgba(')));
expect('fillStyle assigned gradient object', log.some((e) => e[0] === 'set:fillStyle' && e[1] === '<obj>'));

if (failures > 0) { console.error(failures + ' failures'); process.exit(1); }
console.log('REPLAY OK: ' + n + ' commands round-tripped');

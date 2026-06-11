// F-007 node-side proof: instantiate a WasmTarget-compiled module with the
// generated canvas2d glue against a logging ctx, call the export, and assert
// (1) the f64 value-returning import (measureText width) flowed INTO wasm and
// back out the export, (2) wasm USED the value (fillRect width == measured),
// (3) buffered image bytes crossed and landed in putImageData in order.
// Usage: node wasm_e2e_check.js <module.wasm> <glue.js> <export_name>
const fs = require('fs');
const [, , wasmPath, gluePath, exportName] = process.argv;
const glueSrc = fs.readFileSync(gluePath, 'utf8');

globalThis.ImageData = class { constructor(data, w, h) { this.data = data; this.width = w; this.height = h; } };

const log = [];
const ctxState = {};
const loggingCtx = new Proxy({}, {
  get(t, prop) {
    if (prop === 'getContext') return undefined;
    if (prop === 'measureText') return (s) => ({ width: 42, actualBoundingBoxAscent: 9, actualBoundingBoxDescent: 3 });
    if (prop === 'canvas') return { width: 640, height: 480 };
    return (...a) => { log.push([prop, ...a]); };
  },
  set(t, prop, v) { ctxState[prop] = v; return true; },
});

const factory = new Function(glueSrc + '\nreturn canvas2d_imports;')();

(async () => {
  const bytes = fs.readFileSync(wasmPath);
  let instance;
  try {
    ({ instance } = await WebAssembly.instantiate(bytes, {
      canvas2d: factory(loggingCtx),
      Math: { pow: Math.pow },
    }));
  } catch (e) {
    console.error('INSTANTIATE FAIL: ' + e.message);
    process.exit(1);
  }
  const fn = instance.exports[exportName];
  if (typeof fn !== 'function') {
    console.error('MISSING EXPORT "' + exportName + '" — have: ' + Object.keys(instance.exports).join(', '));
    process.exit(1);
  }
  let result;
  try { result = fn(); } catch (e) {
    console.error('TRAP: ' + (e.stack || e.message));
    process.exit(1);
  }

  let failures = 0;
  const expect = (desc, pred) => { if (!pred) { console.error('FAIL: ' + desc); failures++; } };

  expect('export returned the measured width 42 (f64 import → wasm → export)', result === 42);
  expect('wasm USED the measured width: fillRect(0, 90, 42, 5) drawn',
    log.some((e) => e[0] === 'fillRect' && e[1] === 0 && e[2] === 90 && e[3] === 42 && e[4] === 5));
  expect('first fillRect(10, 10, 100, 50) drawn',
    log.some((e) => e[0] === 'fillRect' && e[1] === 10 && e[2] === 10 && e[3] === 100 && e[4] === 50));
  expect("fillText('Hi', ...) from buffered codepoints",
    log.some((e) => e[0] === 'fillText' && e[1] === 'Hi'));
  const pid = log.filter((e) => e[0] === 'putImageData');
  expect('putImageData received 2x1 image', pid.length === 1 && pid[0][1].width === 2 && pid[0][1].height === 1);
  expect('image bytes crossed in order', pid.length === 1 &&
    JSON.stringify(Array.from(pid[0][1].data)) === '[0,255,0,255,0,0,255,255]');

  if (failures > 0) { console.error(failures + ' failures'); process.exit(1); }
  console.log('WASM E2E OK: result=' + result + ', ' + log.length + ' canvas calls');
})();

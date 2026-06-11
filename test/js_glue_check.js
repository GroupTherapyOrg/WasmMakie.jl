// Validates the generated canvas2d glue against the import specs:
// the glue must be syntactically valid JS, expose every op, every op must be
// callable with wasm-shaped args (BigInt for I64, Number for F64), and must
// return the wasm-correct kind (bigint for I64 ops, number for F64 ops).
// Usage: node js_glue_check.js <glue.js> <specs.json>
const fs = require('fs');
const [, , gluePath, specsPath] = process.argv;
const glueSrc = fs.readFileSync(gluePath, 'utf8');
const specs = JSON.parse(fs.readFileSync(specsPath, 'utf8'));

// Browser API stand-ins for node.
globalThis.ImageData = class { constructor(data, w, h) { this.data = data; this.width = w; this.height = h; } };

// An absorber swallows any method chain / property set and stays callable.
const absorber = new Proxy(function () { }, {
  get(t, p) { if (p === Symbol.toPrimitive) return () => 0; return absorber; },
  apply() { return absorber; },
  set() { return true; },
});

const measureResult = new Proxy({}, { get: () => 0 });
const mockCtx = new Proxy({}, {
  get(t, prop) {
    if (prop === 'getContext') return undefined; // we ARE the ctx, not a canvas element
    if (prop === 'measureText') return () => measureResult;
    if (prop === 'canvas') return { width: 640, height: 480 };
    return (...a) => absorber;
  },
  set() { return true; },
});
globalThis.OffscreenCanvas = class { constructor(w, h) { } getContext() { return mockCtx; } };

const factory = new Function(glueSrc + '\nreturn canvas2d_imports;')();
const imports = factory(mockCtx);

let failures = 0;
for (const spec of specs) {
  const fn = imports[spec.name];
  if (typeof fn !== 'function') { console.error('MISSING op: ' + spec.name); failures++; continue; }
  const args = spec.params.map((p) => (p === 'I64' ? 0n : 0.5));
  let out;
  try { out = fn(...args); } catch (e) { console.error('THROWS: ' + spec.name + ' — ' + e.message); failures++; continue; }
  const wantBig = spec.ret === 'I64';
  if (wantBig && typeof out !== 'bigint') { console.error('RET KIND: ' + spec.name + ' expected bigint, got ' + typeof out); failures++; }
  if (!wantBig && typeof out !== 'number') { console.error('RET KIND: ' + spec.name + ' expected number, got ' + typeof out); failures++; }
}
if (failures > 0) { console.error(failures + ' failures'); process.exit(1); }
console.log('JS GLUE OK: ' + specs.length + ' ops callable with correct return kinds');

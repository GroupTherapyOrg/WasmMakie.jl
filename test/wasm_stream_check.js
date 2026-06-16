// Capture the wasm module's canvas2d call stream (the differential's wasm side)
const fs = require('fs');
const [, , wasmPath, gluePath, exportName] = process.argv;
const glueSrc = fs.readFileSync(gluePath, 'utf8');
globalThis.ImageData = class { constructor(d, w, h) { this.data = d; this.width = w; this.height = h; } };
const absorber = new Proxy(function(){}, { get(t,p){ if (p===Symbol.toPrimitive) return ()=>0; return absorber; }, apply(){ return absorber; }, set(){ return true; } });
const measureResult = new Proxy({}, { get: () => 0 });
const mockCtx = new Proxy({}, {
  get(t, prop) {
    if (prop === 'getContext') return undefined;
    if (prop === 'measureText') return () => measureResult;
    if (prop === 'canvas') return { width: 640, height: 480 };
    return (...a) => absorber;
  },
  set() { return true; },
});
globalThis.OffscreenCanvas = class { constructor(){} getContext(){ return mockCtx; } };
const factory = new Function(glueSrc + '\nreturn canvas2d_imports;')();
const base = factory(mockCtx);
const stream = [];
const wrapped = {};
for (const k of Object.keys(base)) {
  wrapped[k] = (...args) => { stream.push({ op: k, args: args.map(a => typeof a === 'bigint' ? Number(a) : a) }); return base[k](...args); };
}
// WasmTarget modules import a js-string builtin (text → fromCharCodeArray) and
// declare an `io` write bridge (unused by these kernels). Opt into the JS
// String Builtins and stub io so instantiation succeeds.
const io = new Proxy({}, { get: () => () => 0 });
(async () => {
  const { instance } = await WebAssembly.instantiate(
    fs.readFileSync(wasmPath),
    { canvas2d: wrapped, Math: { pow: Math.pow }, io },
    { builtins: ['js-string'] },
  );
  try { instance.exports[exportName](); } catch (e) {
    console.error('TRAP after ' + stream.length + ' ops; last 5: ' + JSON.stringify(stream.slice(-5)));
    process.exit(1);
  }
  console.log(JSON.stringify(stream));
})();

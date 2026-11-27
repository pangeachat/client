// Regression for CLIENT-EZG / flutter/flutter#187961. Run after
// `fvm flutter precache --web`: node test/web/canvaskit_memory_test.cjs .fvm/flutter_sdk
// Exercise the shipped native artifacts, not a mock of their JS bindings.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { pathToFileURL } = require('node:url');

(async () => {
  const sdk = fs.realpathSync(process.argv[2] || process.env.FLUTTER_ROOT || '.fvm/flutter_sdk');
  for (const variant of ['', 'chromium']) {
    const dir = path.join(sdk, 'bin/cache/flutter_web_sdk/canvaskit', variant);
    const wasm = new WebAssembly.Module(fs.readFileSync(path.join(dir, 'canvaskit.wasm')));
    const module = await import(pathToFileURL(path.join(dir, 'canvaskit.js')).href);
    const ck = await module.default({
      instantiateWasm(imports, receive) {
        const instance = new WebAssembly.Instance(wasm, imports);
        receive(instance);
        return instance.exports;
      },
    });
    const before = ck.HEAPU8.byteLength;
    for (let i = 0; i < 2000000; i++) {
      const builder = new ck.PathBuilder();
      const fillType = i % 2 ? ck.FillType.EvenOdd : ck.FillType.Winding;
      // Flutter ignores the return value. Before the Skia fix, setFillType
      // returned a new native builder copy which nobody owned or deleted.
      builder.setFillType(fillType);
      if (i < 2) {
        const snapshot = builder.snapshot();
        assert.equal(snapshot.getFillType().value, fillType.value);
        snapshot.delete();
      }
      builder.delete();
    }
    const after = ck.HEAPU8.byteLength;
    console.log(JSON.stringify({ variant: variant || 'default', before, after }));
    // Capacity need not shrink. Reusing this tiny live allocation must fit
    // the initial heap; the old engine grew by 192 MiB in this same loop.
    assert.equal(after, before, 'PathBuilder operations leaked native memory');
  }
})().catch(error => { console.error(error); process.exitCode = 1; });

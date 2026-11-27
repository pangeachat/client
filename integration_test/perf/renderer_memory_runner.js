// Run the local renderer_memory_app.dart build, without credentials or backend
// traffic: node integration_test/perf/renderer_memory_runner.js <build-dir> [seconds] [mode]
// Fail if the CanvasKit heap keeps growing after warmup, or the renderer throws.
const { chromium } = require('@playwright/test');
const http = require('http');
const fs = require('fs');
const path = require('path');

const root = path.resolve(process.argv[2] || 'build/web');
const seconds = Number(process.argv[3] || 90);
const mode = process.argv[4] || 'painter';
if (!Number.isFinite(seconds) || seconds < 60 || !['painter', 'bot'].includes(mode)) {
  throw new Error('Use a duration of at least 60 seconds and mode painter or bot.');
}
const mime = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html', '.json': 'application/json' };

(async () => {
  const server = http.createServer((request, response) => {
    const relative = new URL(request.url, 'http://localhost').pathname;
    // The fixture uses the built engine and application bundle, not the
    // production shell's Firebase/download helpers or legacy worker cleanup.
    if (relative === '/') {
      response.setHeader('Content-Type', 'text/html');
      response.end('<!doctype html><html><head><base href="/"><link rel="icon" href="data:,"></head><body><script src="flutter_bootstrap.js" async></script></body></html>');
      return;
    }
    const file = path.resolve(root, '.' + (relative === '/' ? '/index.html' : relative));
    if (!file.startsWith(root + path.sep) || !fs.existsSync(file)) {
      response.writeHead(404).end();
      return;
    }
    response.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream');
    fs.createReadStream(file).pipe(response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({ channel: 'chrome', headless: true });
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => {
      if (message.type() === 'error') errors.push(message.text());
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/?mode=${mode}`);
    await page.waitForFunction(() => window.flutterCanvasKit?.HEAPU8?.byteLength && window.rendererMemoryFrames > 0, null, { timeout: 60000 });
    const samples = [];
    for (let elapsed = 0; elapsed <= seconds; elapsed += 10) {
      if (elapsed) await page.waitForTimeout(10000);
      const sample = await page.evaluate(() => ({ bytes: window.flutterCanvasKit.HEAPU8.byteLength, frames: window.rendererMemoryFrames }));
      samples.push({ elapsed, ...sample });
      console.log(JSON.stringify({ mode, elapsed, ...sample }));
    }
    const warm = samples.find(sample => sample.elapsed === 20);
    const final = samples.at(-1);
    const growth = final.bytes - warm.bytes;
    const screenshot = path.join(root, `renderer-memory-${mode}.png`);
    await page.screenshot({ path: screenshot });
    console.log(JSON.stringify({ mode, samples, growthAfterWarmup: growth, errors, screenshot }));
    if (errors.length || growth > 32 * 1024 * 1024 || final.frames - warm.frames < 1000) process.exitCode = 1;
  } finally {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });

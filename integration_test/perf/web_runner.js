// Runs a performance-benchmark scenario on web (testing.instructions.md §
// Performance benchmark). Phones use `flutter drive`; web does not, because
// drive's Chrome records a performance trace (which inflates frame times) and
// runs as a guest, so no sign-in survives between runs.
//
// Build the scenario and the normal app with the same script, e.g.
//   ./scripts/build-web-versioned-canvaskit.sh --pwa-strategy=none --profile \
//     -t integration_test/perf/chat_list_perf_test.dart && mv build/web build/perf-web
//   ./scripts/build-web-versioned-canvaskit.sh --pwa-strategy=none --profile && mv build/web build/app-web
// copy .env into each, then:
//   node integration_test/perf/web_runner.js --dir build/app-web --login   (once: sign in, press Enter)
//   node integration_test/perf/web_runner.js --dir build/perf-web
//
// Both builds are served on the same origin with the same saved Chrome
// profile, which is what carries the sign-in from the app into the benchmark.

const { chromium } = require('@playwright/test');
const { spawn, execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const args = process.argv.slice(2);
const opt = (name) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? null : args[i + 1];
};
const DIR = opt('dir');
const PORT = 8097;
const PROFILE_DIR = path.resolve('build/perf/.chrome-profile');
const TIMEOUT_MS = 5 * 60 * 1000;

if (!DIR || !fs.existsSync(path.join(DIR, 'index.html'))) {
  console.error('Pass --dir <a flutter web build directory>.');
  process.exit(2);
}

(async () => {
  const server = spawn('python3', ['-m', 'http.server', String(PORT), '--bind', '127.0.0.1', '--directory', DIR], { stdio: 'ignore' });
  await new Promise((r) => setTimeout(r, 1000));
  const context = await chromium.launchPersistentContext(PROFILE_DIR, {
    channel: 'chrome',
    headless: false,
    viewport: { width: 1400, height: 900 },
    args: ['--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding', '--disable-background-timer-throttling'],
  });
  const done = async (code) => {
    await context.close();
    server.kill();
    process.exit(code);
  };
  const page = context.pages()[0] || (await context.newPage());

  if (args.includes('--login')) {
    await page.goto(`http://localhost:${PORT}/`);
    console.log('Sign in in the browser window, then press Enter here.');
    const rl = readline.createInterface({ input: process.stdin });
    await new Promise((resolve) => rl.once('line', resolve));
    rl.close();
    return done(0);
  }

  // A software renderer makes raster times an order of magnitude too high.
  await page.goto('about:blank');
  const renderer = await page.evaluate(() => {
    const gl = document.createElement('canvas').getContext('webgl2');
    const info = gl && gl.getExtension('WEBGL_debug_renderer_info');
    return gl ? gl.getParameter(info ? info.UNMASKED_RENDERER_WEBGL : gl.RENDERER) : 'no webgl2';
  });
  console.log(`renderer: ${renderer}`);
  if (/SwiftShader|llvmpipe|Software|no webgl2/i.test(renderer)) {
    console.error('Chrome is rendering in software; refusing to measure.');
    return done(2);
  }

  // Flutter web reports every display as 60 Hz, which would judge a 120 Hz
  // display's frames against twice its real budget. Measure it instead.
  const measuredRate = await page.evaluate(
    () =>
      new Promise((resolve) => {
        let frames = 0;
        const start = performance.now();
        const tick = () => {
          frames++;
          const elapsed = performance.now() - start;
          if (elapsed < 1000) requestAnimationFrame(tick);
          else resolve(Math.round((frames * 1000) / elapsed));
        };
        requestAnimationFrame(tick);
      }),
  );
  // A one-second count wobbles by a frame; snap to the nearest standard rate
  // so every run on this display is judged against the same budget.
  const refreshRate = [60, 75, 90, 120, 144, 165, 240].reduce((best, rate) =>
    Math.abs(rate - measuredRate) < Math.abs(best - measuredRate) ? rate : best,
  );
  console.log(`display: ${refreshRate} Hz (measured ${measuredRate})`);

  const outcome = new Promise((resolve) => {
    page.on('console', (msg) => {
      const text = msg.text();
      if (text.startsWith('PERF_RESULT ')) resolve({ result: JSON.parse(text.slice('PERF_RESULT '.length)) });
      else if (text.startsWith('PERF FAILED')) resolve({ failure: text });
      else if (text.startsWith('PERF ')) console.log(text);
    });
    setTimeout(() => resolve({ failure: `No result within ${TIMEOUT_MS / 60000} minutes.` }), TIMEOUT_MS);
  });
  await page.goto(`http://localhost:${PORT}/?refreshRate=${refreshRate}`);
  const { result, failure } = await outcome;
  if (failure) {
    console.error(failure);
    return done(1);
  }

  const dirty = execSync('git status --porcelain').toString().trim() !== '';
  result.commit = execSync('git rev-parse --short HEAD').toString().trim() + (dirty ? '-dirty' : '');
  result.recordedAt = new Date().toISOString();
  result.renderer = renderer;
  const stamp = result.recordedAt.replace(/[:.]/g, '-');
  fs.mkdirSync('build/perf', { recursive: true });
  const file = `build/perf/${result.scenario}_web_${stamp}.json`;
  fs.writeFileSync(file, JSON.stringify(result, null, 2));
  console.log(`Wrote ${file}`);
  return done(0);
})();

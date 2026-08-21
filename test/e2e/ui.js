// Driving the Flutter web app WITHOUT pixel coordinates.
//
// The old driver clicked fixed points like (680,126). Every layout change broke
// it silently -- it kept "passing" by clicking empty space, which is how a stale
// harness came to certify a call flow it was no longer exercising.
//
// Flutter ships a hidden semantics placeholder; clicking it turns on a real DOM
// accessibility tree, so elements can be found by their label instead.
const { wait } = require('../lib_login');

async function enableSemantics(page) {
  const r = await page.evaluate(() => {
    const ph = document.querySelector('flt-semantics-placeholder');
    if (!ph) return 'absent';
    ph.click();
    return 'on';
  });
  await wait(1200);
  return r;
}

/// Every labelled node currently on screen. The debugging tool when a click
/// cannot find its target -- it says what WAS there instead.
async function labels(page) {
  return page.evaluate(() =>
    Array.from(document.querySelectorAll('flt-semantics[aria-label]'))
      .map((e) => e.getAttribute('aria-label'))
      .filter((s) => s && s.trim()),
  );
}

async function findRect(page, label, { exact = false } = {}) {
  return page.evaluate(
    (label, exact) => {
      const nodes = Array.from(
        document.querySelectorAll('flt-semantics[aria-label]'),
      );
      const hit = nodes.find((e) => {
        const l = e.getAttribute('aria-label') || '';
        return exact ? l === label : l.toLowerCase().includes(label.toLowerCase());
      });
      if (!hit) return null;
      const r = hit.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) return null;
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    },
    label,
    exact,
  );
}

async function waitForLabel(page, label, { timeout = 15000, exact = false } = {}) {
  const until = Date.now() + timeout;
  for (;;) {
    const r = await findRect(page, label, { exact });
    if (r) return r;
    if (Date.now() > until) {
      throw new Error(
        `label "${label}" never appeared. On screen: ${JSON.stringify(await labels(page))}`,
      );
    }
    await wait(300);
  }
}

/// Clicks a labelled element, failing loudly if it is not there. A click that
/// misses must never look like a click that worked.
async function clickLabel(page, label, opts = {}) {
  const r = await waitForLabel(page, label, opts);
  await page.mouse.click(r.x, r.y);
  return r;
}

async function hasLabel(page, label) {
  return (await findRect(page, label)) !== null;
}

module.exports = { enableSemantics, labels, findRect, waitForLabel, clickLabel, hasLabel };

// ---------------------------------------------------------------------------
// The incoming-call banner.
//
// Flutter's accessibility tree does NOT include this overlay -- verified by
// dumping every flt-semantics node while a ring was on screen and confirming
// against a screenshot that the banner was plainly visible with none of its
// controls represented. So it cannot be driven by label.
//
// It is therefore driven by position, at coordinates confirmed against a
// screenshot at this viewport. That would normally be the fragile thing that
// rotted the previous harness -- so NOTHING here is trusted: every scenario
// asserts the OUTCOME through the Matrix API afterwards. A click that misses
// produces no decline event and no membership, and the scenario fails loudly
// instead of quietly passing.
const BANNER = {
  decline: { x: 622, y: 126 },
  answer: { x: 680, y: 126 },
  message: { x: 443, y: 126 },
};

async function clickBanner(page, which) {
  const p = BANNER[which];
  if (!p) throw new Error('unknown banner control: ' + which);
  await page.mouse.click(p.x, p.y);
}

module.exports.BANNER = BANNER;
module.exports.clickBanner = clickBanner;

// The in-pane call panel. Same reasoning as BANNER: its controls carry
// Semantics labels in the source but do not reach the accessibility tree, so
// they are clicked by position, confirmed against a screenshot, and every use
// is followed by a server-side assertion that the action actually happened.
const PANEL = {
  hangup: { x: 450, y: 602 },
  mute: { x: 366, y: 602 },
  camera: { x: 548, y: 602 },
  minimize: { x: 133, y: 104 },
  fullscreen: { x: 797, y: 104 },
};

async function clickPanel(page, which) {
  const p = PANEL[which];
  if (!p) throw new Error('unknown panel control: ' + which);
  await page.mouse.click(p.x, p.y);
}

module.exports.PANEL = PANEL;
module.exports.clickPanel = clickPanel;

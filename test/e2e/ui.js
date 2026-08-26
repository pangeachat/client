const labelsModule = require('./labels');
// Driving the Flutter web app WITHOUT pixel coordinates.
//
// The old driver clicked fixed points like (680,126). Every layout change broke
// it silently -- it kept "passing" by clicking empty space, which is how a stale
// harness came to certify a call flow it was no longer exercising.
//
// Flutter ships a hidden semantics placeholder; clicking it turns on a real DOM
// accessibility tree, so elements can be found by their label instead.
// Defined here rather than imported, because login.js drives this file:
// the other direction would be a require cycle.
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

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
      const matches = nodes.filter((e) => {
        const l = e.getAttribute('aria-label') || '';
        const ok = exact ? l === label : l.toLowerCase().includes(label.toLowerCase());
        if (!ok) return false;
        const r = e.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
      });
      if (!matches.length) return null;
      // A real control, in preference to anything else carrying the same label.
      // An IconButton's TOOLTIP repeats its label, so once the pointer has
      // rested on the call button a second node with aria-label "Call" exists --
      // and clicking that one does nothing at all. That is what made the second
      // call in a session silently fail to place.
      const hit = matches.find((e) => e.getAttribute('role') === 'button') || matches[0];
      const r = hit.getBoundingClientRect();
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

/// The same questions, asked about a CONTROL rather than an English string.
///
/// The app renders in the user's own language, so "is the call button there"
/// cannot be asked as "is the text 'Call' there". Each of these tries every
/// string the app could draw for that control -- see labels.js -- and answers
/// on the first one the screen actually has.
/// EXACT by default, and that is not a detail.
///
/// A control's candidates are whole labels, so a substring match is never what
/// is wanted here -- and it is actively dangerous: "Call" is a substring of
/// "Video call", so a loose match places a VIDEO call when the scenario asked
/// for a voice one, and the failure surfaces four assertions later as a card
/// reading "Missed video call". Every call site this replaced passed
/// `exact: true` for that reason; losing it in the abstraction put the bug
/// back.
async function findControl(page, name, opts = {}) {
  for (const text of labelsModule.candidates(name)) {
    const rect = await findRect(page, text, { exact: true, ...opts });
    if (rect) return rect;
  }
  return null;
}

async function hasControl(page, name, opts = {}) {
  return (await findControl(page, name, opts)) !== null;
}

/// Waits for a control to appear, then clicks it.
///
/// WAITS, like `clickLabel` does. An earlier version of this probed once and
/// gave up, which quietly changed what several scenarios were asking: "the
/// call button is usable again right after hanging up" stopped meaning "it
/// comes back" and started meaning "it is back this instant". The suite
/// caught it, which is the whole reason it exists.
async function clickControl(page, name, { timeout = 15000, ...opts } = {}) {
  const until = Date.now() + timeout;
  for (;;) {
    const rect = await findControl(page, name, opts);
    if (rect) {
      await page.mouse.click(rect.x, rect.y);
      return rect;
    }
    if (Date.now() > until) {
      throw new Error(
        `${name} never appeared. Tried ` +
          `${labelsModule.candidates(name).length} translations. ` +
          `On screen: ${JSON.stringify(await labels(page))}`,
      );
    }
    await wait(300);
  }
}

/// The same wait, without the click.
async function waitForControl(page, name, { timeout = 15000, ...opts } = {}) {
  const until = Date.now() + timeout;
  for (;;) {
    const rect = await findControl(page, name, opts);
    if (rect) return rect;
    if (Date.now() > until) {
      throw new Error(
        `${name} never appeared. On screen: ${JSON.stringify(await labels(page))}`,
      );
    }
    await wait(300);
  }
}

module.exports = {
  wait, enableSemantics, labels, findRect, waitForLabel, clickLabel, hasLabel,
  findControl, hasControl, clickControl, waitForControl,
};

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

const BANNER_LABELS = { answer: 'answer', decline: 'decline', message: 'message' };

/// Same rule as the panel: label first, confirmed position as the fallback,
/// and the caller proves on the server that it landed.
async function clickBanner(page, which) {
  const label = BANNER_LABELS[which];
  if (label) {
    const r = await findRect(page, label);
    if (r) {
      await page.mouse.click(r.x, r.y);
      return 'label';
    }
  }
  const p = BANNER[which];
  if (!p) throw new Error('unknown banner control: ' + which);
  await page.mouse.click(p.x, p.y);
  return 'position';
}

module.exports.BANNER = BANNER;
module.exports.BANNER_LABELS = BANNER_LABELS;
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

const PANEL_LABELS = {
  hangup: 'Hang up',
  mute: 'Mute',
  camera: 'Turn camera on',
  minimize: 'Minimize call',
  fullscreen: 'Full screen',
};

/// Prefers the accessibility label; falls back to the confirmed position only
/// if the control is genuinely not in the tree. Either way the caller asserts
/// the OUTCOME on the server, so a miss can never pass quietly.
async function clickPanel(page, which) {
  const label = PANEL_LABELS[which];
  if (label) {
    const r = await findRect(page, label);
    if (r) {
      await page.mouse.click(r.x, r.y);
      return 'label';
    }
  }
  const p = PANEL[which];
  if (!p) throw new Error('unknown panel control: ' + which);
  await page.mouse.click(p.x, p.y);
  return 'position';
}

module.exports.PANEL = PANEL;
module.exports.PANEL_LABELS = PANEL_LABELS;
module.exports.clickPanel = clickPanel;

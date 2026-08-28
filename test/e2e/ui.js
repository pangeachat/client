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

/// Every semantics node on screen: the names it answers to, its role, and
/// where it is. One crossing of the browser boundary; every question below is
/// answered from it, in node.
///
/// A NAME IS NOT ONLY AN ARIA-LABEL. Flutter's web engine publishes a node's
/// accessible name two ways and the choice is the ENGINE's, not the app's: a
/// node that has child semantics nodes carries `aria-label`, and a LEAF carries
/// its name as its own DOM TEXT instead. This file used to read only the
/// attribute, so every leaf control was invisible to it -- and a leaf is
/// exactly what a tappable widget with no inner semantics becomes.
///
/// What that cost: `hasControl(page, 'transcriptLink')` could never once be
/// true. The call card publishes "Read the transcript" as text, so the check
/// that asks whether the card offers the transcript failed on every run of a
/// feature that was working perfectly -- and the check it gates, the one about
/// nobody being wrongly called silent, has therefore never run at all. It
/// looked like a routing bug: `ui.labels()` came back with the map's labels
/// and nothing of the chat, so an OPEN room read as the bare world map with
/// the deep link swallowed. There turned out to be a real swallow as well (see
/// harness.js's [openRoom]), which is exactly why an unreadable screen is
/// expensive: it made a rare bug and a common one look like the same thing.
///
/// login.js already read both (its own `nameOf`), which is why signing in kept
/// working while everything after it did not; unstick.js and refresh_midcall.js
/// each grew their own leaf-text fallback. This is the one place that knows.
///
/// A merged leaf's name is the CONCATENATION of everything merged into it --
/// "Read the transcript\nRead the transcript\nVoice call\n  0:38" is a single
/// node -- so its text is offered LINE BY LINE rather than whole. Matching the
/// blob would need a substring test, and substrings are precisely what
/// `findControl` refuses: "Call" is a substring of "Video call", and that
/// mistake places a video call where a scenario asked for a voice one.
async function scan(page) {
  return page.evaluate(() => {
    const nodes = Array.from(document.querySelectorAll('flt-semantics'));
    const out = [];
    for (const e of nodes) {
      const names = [];
      const aria = (e.getAttribute('aria-label') || '').trim();
      if (aria) names.push(aria);
      // The node's OWN text only. Descendant text would make every ancestor
      // answer to every name beneath it, up to the root -- and the root is a
      // full-screen node, so a click would land in the middle of the window.
      for (const child of e.childNodes) {
        if (child.nodeType !== Node.TEXT_NODE) continue;
        for (const line of (child.textContent || '').split('\n')) {
          const t = line.trim();
          if (t) names.push(t);
        }
      }
      if (!names.length) continue;
      const r = e.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0) continue;
      const x = r.x + r.width / 2;
      const y = r.y + r.height / 2;
      const onScreen =
        x >= 0 && y >= 0 && x < window.innerWidth && y < window.innerHeight;
      // Would a click at that point actually reach this node? Being inside the
      // window is not enough: Flutter does NOT clip the semantics DOM to its
      // scroll views, so a card scrolled out of a chat list keeps a node
      // positioned wherever it would have been -- often over the app bar, at a
      // perfectly plausible-looking coordinate. Clicking it presses whatever is
      // genuinely there instead, and nothing about the miss looks like a miss.
      // The node itself, or something INSIDE it (a labelled button's own
      // tappable child). Never an ancestor: `flutter-view` contains every
      // node on the page, so accepting one would call everything reachable
      // and answer the question with "yes" for ever.
      const at = onScreen ? document.elementFromPoint(x, y) : null;
      out.push({
        names,
        role: e.getAttribute('role'),
        x,
        y,
        onScreen,
        hittable: !!at && (at === e || e.contains(at)),
      });
    }
    return out;
  });
}

/// Every name currently on screen, in document order, deduplicated. The
/// debugging tool when a click cannot find its target -- it says what WAS
/// there instead.
async function labels(page) {
  const seen = new Set();
  for (const node of await scan(page)) {
    for (const name of node.names) seen.add(name);
  }
  return [...seen];
}

/// Which of the nodes that answer to a name gets clicked, as a point.
///
/// A real control, in preference to anything else carrying the same name. An
/// IconButton's TOOLTIP repeats its label, so once the pointer has rested on
/// the call button a second node saying "Call" exists -- and clicking that one
/// does nothing at all. That is what made the second call in a session
/// silently fail to place.
///
/// Reachable first, then merely on screen, then anything. A long timeline holds
/// twenty cards with the same name and most of them are scrolled out of the
/// list's clip; their nodes stay in the tree at coordinates that are sometimes
/// negative and sometimes -- worse -- land on the app bar, where a click
/// presses something else entirely and the miss looks like a working click.
///
/// The last tier is a deliberate floor: something answering to the name but
/// unreachable still beats nothing, so `hasControl` stays at least as willing
/// to find a control as it was before this ranking existed.
function choose(matches) {
  if (!matches.length) return null;
  const pick = (list) => list.find((n) => n.role === 'button') || list[0];
  const tiers = [
    matches.filter((n) => n.hittable),
    matches.filter((n) => n.onScreen),
    matches,
  ];
  const hit = pick(tiers.find((t) => t.length));
  return { x: hit.x, y: hit.y };
}

async function findRect(page, label, { exact = false } = {}) {
  const wanted = exact
    ? (name) => name === label
    : (name) => name.toLowerCase().includes(label.toLowerCase());
  return choose((await scan(page)).filter((n) => n.names.some(wanted)));
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
///
/// Asked of ONE reading of the screen, not one per translation. A control has
/// around a hundred candidate strings, and probing them in turn crossed the
/// browser boundary a hundred times for a single question -- slow enough that
/// the screen could change while the answer was being computed, which is the
/// shape of a check that fails for a reason that is not a bug.
async function findControl(page, name, opts = {}) {
  const { exact = true } = opts;
  const candidates = labelsModule.candidates(name);
  const matches = (name_) =>
    exact
      ? candidates.includes(name_)
      : candidates.some((c) => name_.toLowerCase().includes(c.toLowerCase()));
  return choose((await scan(page)).filter((n) => n.names.some(matches)));
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
  wait, enableSemantics, scan, choose, labels, findRect, waitForLabel,
  clickLabel, hasLabel, findControl, hasControl, clickControl, waitForControl,
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

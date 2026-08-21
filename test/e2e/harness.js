// The call end-to-end harness.
//
// Two real browsers with fake microphones, driven by ACCESSIBILITY LABEL and
// URL rather than pixel coordinates, and asserted against the Matrix
// client-server API rather than against the canvas.
//
// The previous harness did the opposite of both and rotted silently: its fixed
// clicks landed on empty space after a layout change, so it "passed" a call flow
// it was no longer exercising. Every check here fails loudly instead.
const { launch } = require('../lib');
const { login, wait } = require('../lib_login');
const ui = require('./ui');
const mx = require('./matrix');

const APP = process.env.APP_URL || 'http://localhost:8091';

const ACCOUNTS = {
  learner: { user: 'learner', pass: 'learnerpass', profile: '/tmp/callweb/learner-profile', wav: '/tmp/caller.wav' },
  calltester: { user: 'calltester', pass: 'calltesterpass', profile: '/tmp/callweb/calltester-profile', wav: '/tmp/callee.wav' },
};

/// One participant: a browser, a page, and an API token for assertions.
async function openParticipant(name, roomLocalpart, port) {
  const a = ACCOUNTS[name];
  const browser = await launch({ userDataDir: a.profile, wav: a.wav, port });
  const page = (await browser.pages())[0];
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e.stack || e.message || e).slice(0, 600)));
  await login(page, a.user, a.pass, 'x');
  await wait(3000);
  await openRoom(page, roomLocalpart);
  const session = await mx.login(a.user, a.pass);
  return { name, browser, page, errors, ...session };
}

/// Opens the room and PROVES it opened.
///
/// The deep link does not always stick -- the app can resolve its own route
/// after login and land back on the activity map. A harness that did not check
/// would then drive the map, find nothing, and report the feature broken (or
/// worse, find nothing and report nothing). So this confirms by waiting for a
/// control that only exists inside a chat, and fails loudly if it never comes.
async function openRoom(page, roomLocalpart, attempts = 4) {
  for (let i = 1; i <= attempts; i++) {
    await page.goto(`${APP}/?left=chats,room:${roomLocalpart}`, { waitUntil: 'domcontentloaded' });
    await wait(i === 1 ? 6500 : 4000);
    await ui.enableSemantics(page);
    await wait(1500);
    if (await ui.hasLabel(page, 'Call')) return;
    console.log(`   (room did not open, attempt ${i}/${attempts}; on screen: ${JSON.stringify(await ui.labels(page))})`);
  }
  throw new Error('could not open the room: the call controls never appeared');
}

/// Re-opens the room if the app has drifted away from it.
///
/// The router re-resolves its own route once the initial sync finishes and can
/// land back on the activity map minutes after the room was opened. Checking
/// once at startup is therefore not enough: every scenario re-asserts the room
/// is actually on screen before it touches anything.
async function ensureRoom(p, roomLocalpart) {
  if (await ui.hasLabel(p.page, 'Call')) return;
  console.log(`   (${p.name} drifted off the room; reopening)`);
  await openRoom(p.page, roomLocalpart);
}

/// Recovers a client after a scenario that ANSWERED a call.
///
/// With semantics enabled, ending an answered call leaves the Flutter web
/// engine's semantics click pipeline broken: every later click throws
/// "Cannot read properties of null (reading '_values')" inside the engine's
/// ClickDebouncer, before any app code runs -- so buttons silently stop
/// working. Verified to be semantics-specific: the identical flow driven by
/// raw coordinates with semantics off works perfectly, which is why ordinary
/// users never see it. A reload is the only reliable reset; the semantics
/// placeholder cannot be re-enabled a second time without one.
async function recover(p, roomLocalpart) {
  await p.page.reload({ waitUntil: 'domcontentloaded' });
  await wait(6000);
  await ui.enableSemantics(p.page);
  await wait(1500);
  await openRoom(p.page, roomLocalpart);
  // Reloading re-registers the engine error hooks' state, so stale errors from
  // the pre-reload page are not counted against later scenarios.
  p.errors.length = 0;
}

/// Performs an action until the SERVER says it happened.
///
/// The banner and the call panel are clicked by position, and a click can land
/// a moment before the control is painted or while the app is mid-rebuild. A
/// single click plus a fixed sleep makes the whole suite timing-sensitive and
/// produces failures that look like product bugs. Retrying against a
/// server-side predicate removes the timing question entirely: it either
/// happened, or it genuinely did not.
async function actUntil(label, act, confirmed, { tries = 6, gap = 2500 } = {}) {
  for (let i = 1; i <= tries; i++) {
    if (await confirmed()) return true;
    await act();
    await wait(gap);
    if (await confirmed()) return true;
    if (i < tries) console.log(`   (${label}: not confirmed yet, retry ${i}/${tries - 1})`);
  }
  return await confirmed();
}

/// Everything in the room from this moment on. Scenarios assert on the DELTA,
/// so a room with history behaves the same as an empty one.
async function mark(token, roomId) {
  const evs = await mx.timeline(token, roomId, 5);
  return evs.length ? evs[evs.length - 1].event_id : null;
}

async function since(token, roomId, markerId) {
  const evs = await mx.timeline(token, roomId, 80);
  if (!markerId) return evs;
  const i = evs.findIndex((e) => e.event_id === markerId);
  return i === -1 ? evs : evs.slice(i + 1);
}

/// The heart of it: what did the two participants each end up with?
function compare(aEvents, aId, bEvents, bId) {
  const aIds = new Set(aEvents.map((e) => e.event_id));
  const bIds = new Set(bEvents.map((e) => e.event_id));
  return {
    onlyA: aEvents.filter((e) => !bIds.has(e.event_id)).map((e) => e.type),
    onlyB: bEvents.filter((e) => !aIds.has(e.event_id)).map((e) => e.type),
    aCards: mx.cardsIn(aEvents, aId),
    bCards: mx.cardsIn(bEvents, bId),
  };
}

const results = [];
function check(scenario, name, pass, detail) {
  results.push({ scenario, name, pass, detail });
  console.log(`   ${pass ? 'PASS' : 'FAIL'}  ${name}${pass ? '' : '  -> ' + detail}`);
}

function report() {
  const failed = results.filter((r) => !r.pass);
  console.log('\n================ SUMMARY ================');
  console.log(`checks: ${results.length}   passed: ${results.length - failed.length}   FAILED: ${failed.length}`);
  failed.forEach((f) => console.log(`  FAIL [${f.scenario}] ${f.name}: ${f.detail}`));
  return failed.length;
}

module.exports = { openParticipant, openRoom, ensureRoom, actUntil, recover, mark, since, compare, check, report, results, ui, mx, wait, APP };

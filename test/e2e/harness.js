// The call end-to-end harness.
//
// Two real browsers with fake microphones, driven by ACCESSIBILITY LABEL and
// URL rather than pixel coordinates, and asserted against the Matrix
// client-server API rather than against the canvas.
//
// The previous harness did the opposite of both and rotted silently: its fixed
// clicks landed on empty space after a layout change, so it "passed" a call flow
// it was no longer exercising. Every check here fails loudly instead.
const { launch } = require('./browser');
const { login, wait } = require('./login');
const ui = require('./ui');
const mx = require('./matrix');
const cfg = require('./config');

const APP = cfg.appUrl;
const ACCOUNTS = cfg.accounts;

/// One participant: a browser, a page, and an API token for assertions.
/// Refuses to run two scenario processes at once.
///
/// Two suites driving the SAME two accounts fight over the same rooms and the
/// same Chrome profiles, and the symptom is nothing like the cause: the app
/// looks broken ("the call controls never appeared", "no ring reached the
/// room") when in truth another run just took the room away. Killing the
/// browsers between runs is not enough -- the node process that drives them
/// has to be gone too.
function refuseIfAnotherRunIsLive() {
  const { execSync } = require('child_process');
  let out = '';
  try {
    // Matched on the FILE NAME with any path in front of it. The pattern used
    // to assume the scenario was started from inside this folder; run as
    // `node test/e2e/scenarios.js` from the repo root it matched nothing at
    // all, and a guard that never fires is worse than no guard, because
    // everyone believes it is watching.
    out = execSync(
      'pgrep -f "node ([^ ]*/)?(scenarios|rejoin_ui|refresh_[a-z_]+|grey_hover'
        + '|list_preview|device[a-z_0-9]*)\\.js" || true',
      { encoding: 'utf8' },
    );
  } catch (_) {
    return;
  }
  // Our own pid, and the shell pgrep runs in -- whose command line contains
  // the pattern itself.
  const mine = new Set([process.pid, process.ppid]);
  const others = out.split('\n').filter((p) => p.trim() && !mine.has(Number(p)));
  if (others.length) {
    throw new Error(
      `another scenario run is still live (pids ${others.join(', ')}); ` +
        'stop it before starting this one, or the two will fight over the room',
    );
  }
}

async function openParticipant(name, roomLocalpart, port) {
  const a = ACCOUNTS[name];
  // The flutter service worker in a persisted profile serves the PREVIOUS
  // build on reload -- every "regression" it manufactures looks exactly like
  // a product bug in whatever changed last. Purging the SW store (login
  // lives in localStorage/IndexedDB and survives) makes each run test the
  // bundle actually on disk.
  try {
    require('fs').rmSync(`${a.profile}/Default/Service Worker`, { recursive: true, force: true });
  } catch (_) {}
  const browser = await launch({ userDataDir: a.profile, wav: a.wav, port });
  const page = (await browser.pages())[0];
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e.stack || e.message || e).slice(0, 600)));
  // Tagged by participant: one shared tag meant the second login's
  // screenshots overwrote the first's, and the evidence for a failure was
  // whichever browser happened to fail last.
  await login(page, a.user, a.pass, name);
  await wait(3000);
  await openRoom(page, roomLocalpart);
  const session = await mx.login(a.user, a.pass);
  return { name, browser, page, errors, ...session };
}

/// Whether an error is just the page having moved under a read.
///
/// Ordinary inside [openRoom]: the loop reads a page it has only this moment
/// told to navigate, and the read's execution context goes away underneath it.
/// The next round asks again.
///
/// Anything else is the HARNESS being broken -- an l10n key the app renamed
/// (labels.js throws by design), a scan that cannot run -- and must be raised.
/// Reported as "the room did not open" it would send whoever reads it looking
/// at the product, which is a long way from the actual fault.
const isMidNavigation = (e) =>
  /execution context|detached|navigat/i.test(String(e && e.message));

/// Opens the room and PROVES it opened.
///
/// A harness that did not check would drive the map, find nothing, and report
/// the feature broken (or worse, find nothing and report nothing). So this
/// confirms by waiting for a control that only exists inside a chat, and fails
/// loudly if it never comes.
///
/// It catches TWO different failures, and they were confused for each other
/// for a long time because this function reported neither of them clearly.
///
///   - The route really was swallowed. Measured with a History API hook, one
///     cold load in ten pushed `/` over the accepted deep link ~160ms later:
///     a restored session announcing itself and being sent to the world map
///     (fixed in the app -- PAuthGaurd.loggedInLanding).
///   - The chat was merely slow to paint. Nothing was wrong with the URL; the
///     app was busy, most visibly right after a call, and a single look 6.5
///     seconds in was too early.
///
/// So: patience for the second ([settledInRoom]), and a failure line that
/// prints the URL, because that is the one fact that tells them apart.
async function openRoom(page, roomLocalpart, attempts = 4) {
  for (let i = 1; i <= attempts; i++) {
    // Cleared first on a retry: the app restores whatever route it was last
    // on, and a profile left sitting on a settings page just swallowed the
    // deep link four times in a row and reported the product broken. Going
    // to the root and letting it settle puts it somewhere the link can work
    // from.
    if (i > 1) {
      await page.goto(`${APP}/`, { waitUntil: 'domcontentloaded' });
      await wait(3000);
      await page.keyboard.press('Escape').catch(() => {});
    }
    await page.goto(`${APP}/?left=chats,room:${roomLocalpart}`, { waitUntil: 'domcontentloaded' });
    if (await settledInRoom(page)) return;
    // The deep link does not always land, and the app then sits on the chat
    // LIST with the conversation right there. Clicking it is what a person
    // would do, and it is far more reliable than reloading the same link
    // again: a row is recognisable by its timestamp.
    //
    // Through the same chooser every other click goes through. "Inside the
    // window" is not the test: a row scrolled out of the list keeps a node at a
    // coordinate that can sit over the app bar, and clicking that presses the
    // app bar. [ui.choose] ranks by what a click would actually reach.
    let onScreen = [];
    try {
      onScreen = await ui.scan(page);
    } catch (e) {
      // Same rule as the wait above: a page still moving is not a reason to
      // abandon a loop whose next act is to reload it anyway.
      if (!isMidNavigation(e)) throw e;
    }
    const row = ui.choose(
      onScreen.filter((n) =>
        n.names.some((l) => /\d{1,2}:\d{2}\s?(AM|PM)/i.test(l))),
      { reachable: true });
    if (row) {
      await page.mouse.click(row.x, row.y);
      if (await settledInRoom(page, { timeout: 8000 })) return;
    }
    // THE URL, always. Without it this line cannot tell the two failures
    // apart, and they want opposite fixes: a link the app REWROTE versus the
    // link still standing with the chat simply not painted yet. It used to
    // print only the labels, and the labels of an OPEN chat are nearly the
    // labels of the bare map -- so a slow paint and a lost route read
    // identically, and an investigation spent a long time on the wrong one.
    // Best effort, and only here. [labels] consults nothing of the app's, so
    // the only way it fails is the page moving -- and by this line a real
    // harness fault has already been raised by the wait above, which asks the
    // same page the same way. A diagnostic that threw would cost the retry
    // that was about to happen. The URL needs no execution context and always
    // survives.
    const seen = await ui
      .labels(page)
      .catch((e) => [`<could not read the screen: ${e.message}>`]);
    console.log(
      `   (room did not open, attempt ${i}/${attempts}; url ${page.url()}; ` +
        `on screen: ${JSON.stringify(seen)})`);
  }
  throw new Error('could not open the room: the call controls never appeared');
}

/// Waits for the chat to be on screen, rather than sleeping and looking once.
///
/// The sleep was 6.5 seconds and it was a guess about a machine, not a fact
/// about the product: right after a call the app is draining a recording,
/// uploading two transcript halves and catching up a sync backlog, and the
/// chat paints later than that. The single look then reported the deep link
/// dead while it was merely early -- the next attempt, doing exactly the same
/// thing, found the room.
///
/// Semantics is re-enabled every round on purpose. Flutter only publishes its
/// placeholder once the engine is up, so a click that arrives before that does
/// nothing at all and the tree stays off for ever; asking again costs nothing
/// once it is on.
async function settledInRoom(page, { timeout = 25000 } = {}) {
  const deadline = Date.now() + timeout;
  let midNavigation = null;
  for (;;) {
    // Best effort: the placeholder is not there before the engine is up, and
    // a failure to click it shows up a line later as a screen that cannot be
    // read -- which IS reported.
    await ui.enableSemantics(page).catch(() => {});
    try {
      if (await ui.hasControl(page, 'call')) return true;
    } catch (e) {
      if (!isMidNavigation(e)) throw e;
      midNavigation = e;
    }
    if (Date.now() > deadline) {
      if (midNavigation) {
        console.log(
          `   (the page never stopped navigating: ${midNavigation.message})`);
      }
      return false;
    }
    await wait(1000);
  }
}

/// Re-opens the room if the app has drifted away from it.
///
/// The router re-resolves its own route once the initial sync finishes and can
/// land back on the activity map minutes after the room was opened. Checking
/// once at startup is therefore not enough: every scenario re-asserts the room
/// is actually on screen before it touches anything.
async function ensureRoom(p, roomLocalpart) {
  if (await ui.hasControl(p.page, 'call')) return;
  console.log(`   (${p.name} drifted off the room; reopening)`);
  await openRoom(p.page, roomLocalpart);
}

/// Kills a participant's browser the way a crash does: no unload, no goodbye.
///
/// `browser.close()` is a POLITE close. Chrome runs the page's unload path on
/// the way out, the app tears its call down, and the SDK RETRACTS the call
/// membership -- which is precisely what a device that died cannot do. The
/// survivor then sees a retraction land with the departure, reads it as "they
/// pressed end" (correctly), and ends the call at once instead of holding the
/// dropped peer's place for the grace.
///
/// So a scenario that means "this device is gone" cannot say `close()`. It has
/// to take the process out from under Chrome, which is what SIGKILL does: no
/// unload handler runs, nothing is retracted, and the membership is left
/// standing exactly as a crash leaves it.
///
/// Verified from the room's own timeline: under `close()` the peer's
/// retraction lands at the moment of the close, where a SERVER-applied leave
/// could not arrive for another 19-30 seconds.
async function kill(participant) {
  const proc = participant.browser.process();
  if (proc) {
    proc.kill('SIGKILL');
    // The socket dies with the process; puppeteer's own disconnect tidies the
    // client side, and awaiting `close()` here would hang on a corpse.
    participant.browser.disconnect?.();
  } else {
    // No handle to the process (a browser we connected to rather than
    // launched). Say so rather than closing politely and pretending.
    throw new Error(
      'cannot kill this browser: no child process handle, so a "crash" here '
      + 'would really be a polite close and would retract the membership',
    );
  }
  await wait(1500);
}

/// Reloads a page the way a user does, and WAKES it up again.
///
/// Flutter web only publishes a semantics tree once the placeholder has been
/// clicked, and a reload throws that away with the rest of the document. A
/// scenario that reloads and then reads text sees an empty page forever and
/// reports the product broken -- which is exactly what happened to the rejoin
/// checks: they spent a minute waiting for text that could never arrive, and
/// by the time they looked, the grace they meant to test had already expired.
/// So no scenario reloads by hand; they all come through here.
async function wake(page, { timeout = 45000 } = {}) {
  await page.reload({ waitUntil: 'domcontentloaded' });
  const deadline = Date.now() + timeout;
  await wait(5000);
  while (Date.now() < deadline) {
    await ui.enableSemantics(page);
    const text = await page
      .evaluate(() => document.body.innerText || '')
      .catch(() => '');
    if (text.trim().length > 0) return true;
    await wait(2000);
  }
  return false;
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

/// A scenario that could not judge itself this run.
///
/// Not a pass and not a failure: a ring that expired before the reload
/// finished has nothing left to answer, and asserting either way would be
/// making it up. It has to reach the SUMMARY though -- a run where a scenario
/// asserted nothing read as fully green, and the only trace was a line of
/// console output nobody scrolls back to.
const inconclusive = [];
function skipped(scenario, name, why) {
  inconclusive.push({ scenario, name, why });
  console.log(`   SKIP  ${name}  -> ${why}`);
}

function report() {
  const failed = results.filter((r) => !r.pass);
  console.log('\n================ SUMMARY ================');
  console.log(`checks: ${results.length}   passed: ${results.length - failed.length}   FAILED: ${failed.length}`);
  failed.forEach((f) => console.log(`  FAIL [${f.scenario}] ${f.name}: ${f.detail}`));
  if (inconclusive.length) {
    console.log(`INCONCLUSIVE: ${inconclusive.length} -- these proved nothing this run`);
    inconclusive.forEach((s) => console.log(`  SKIP [${s.scenario}] ${s.name}: ${s.why}`));
  }
  return failed.length;
}

module.exports = {
  wake, kill, refuseIfAnotherRunIsLive, openParticipant, openRoom, ensureRoom, actUntil,
  recover, mark, since, compare, check, skipped, report, results, inconclusive,
  ui, mx, wait, cfg, APP,
};

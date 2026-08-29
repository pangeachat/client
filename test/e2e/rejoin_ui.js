// The four review fixes, browser to browser -- the same shared Dart the
// phone runs, so this is where they are proven first and cheapest.
//
//  1 a rejoined side's clock CONTINUES the call (both screens agree)
//  2 after the other side ends, nothing still claims "reconnecting"
//  3 the Return banner's red end ENDS the call for the other side
//  4 the chat list previews the call, not the membership plumbing
const labels = require('./labels');
const h = require('./harness');
const { ui, mx, wait } = h;

// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM, roomId: ROOM_ID } = h.cfg;

async function text(page) {
  try { return await page.evaluate(() => document.body.innerText || ''); }
  catch { return ''; }
}

/// The call clock as seconds, read off whichever surface shows it.
/// Every M:SS on the page, in order.
///
/// The room's timeline is full of them: every past call leaves a card reading
/// "Voice call 0:13". Taking the first match read a CARD and called it the
/// call timer -- it never moved, so a frozen number passed for a running one
/// and a rejoin that restarted the clock would have passed too.
function allClocks(pageText) {
  return [...(pageText || '').matchAll(/\b(\d+):(\d{2})\b/g)]
    .map((m) => Number(m[1]) * 60 + Number(m[2]));
}

/// Makes sure the call is SHOWING before anything tries to read its timer.
///
/// A call whose room was re-opened keeps running but collapses to a tile, and
/// a tile has no clock. A scenario that read the page then found only the
/// timeline's "Voice call 0:13" cards -- frozen numbers that pass for a
/// running one.
async function ensurePanel(page) {
  if (await ui.hasControl(page, 'hangup').catch(() => false)) return true;
  await ui.clickPanel(page, 'fullscreen').catch(() => {});
  await wait(1500);
  return ui.hasControl(page, 'hangup').catch(() => false);
}

/// The one that is actually RUNNING, proved by watching it move.
///
/// A card cannot tick; the call timer cannot help it. Nothing else on the
/// page tells them apart reliably, and asking the DOM which subtree is the
/// panel breaks whenever the panel moves.
async function liveClock(page, { gap = 3200 } = {}) {
  const before = allClocks(await text(page));
  await wait(gap);
  const after = allClocks(await text(page));
  for (let i = 0; i < Math.min(before.length, after.length); i++) {
    const moved = after[i] - before[i];
    if (moved >= 2 && moved <= 8) return after[i];
  }
  // The lists can shift when a card appears mid-read; fall back to any value
  // that is present after and advanced from SOME earlier value.
  for (const v of after) {
    if (before.some((b) => v - b >= 2 && v - b <= 8)) return v;
  }
  return -1;
}

/// Clicks the first node carrying ANY of [names] -- the l10n key's known
/// translations, so the account's own interface language does not matter.
async function clickAnyLabel(page, names) {
  return page.evaluate((wanted) => {
    const nodes = [...document.querySelectorAll('flt-semantics, [role=button], button, [aria-label]')];
    const hit = nodes.find((n) => {
      const t = `${n.textContent || ''} ${(n.getAttribute && n.getAttribute('aria-label')) || ''}`;
      return wanted.some((w) => w && t.includes(w));
    });
    if (hit) { hit.click(); return true; }
    return false;
  }, names);
}

async function clickByText(page, label) {
  return page.evaluate((want) => {
    const nodes = [...document.querySelectorAll('flt-semantics, [role=button], button, [aria-label]')];
    const hit = nodes.find((n) =>
      new RegExp(`(^|\\s)${want}(\\s|$)`, 'i').test(n.textContent || '') ||
      new RegExp(`(^|\\s)${want}(\\s|$)`, 'i').test(n.getAttribute?.('aria-label') || ''));
    if (hit) { hit.click(); return true; }
    return false;
  }, label);
}

async function connect(A, B, mA) {
  const rang = await h.actUntil('place',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickControl(A.page, 'call').catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 });
  if (!rang) return false;
  await wait(3500);
  return h.actUntil('answer', async () => { await ui.clickBanner(B.page, 'answer'); },
    () => mx.hasMembership(B.token, ROOM_ID, B.userId), { tries: 5, gap: 3000 });
}

h.refuseIfAnotherRunIsLive();

(async () => {
  const A = await h.openParticipant('learner', ROOM, 9811);
  const B = await h.openParticipant('calltester', ROOM, 9812);
  const bLogAll = [];
  B.page.on('console', (m) => {
    const t = m.text();
    if (/PROBE|breadcrumb|Rejoin|Return|announce|membership/i.test(t)) bLogAll.push(t.slice(0, 220));
  });
  B.page.on('pageerror', (e) => bLogAll.push('PAGEERROR ' + String(e.message).slice(0, 180)));
  let mA = await h.mark(A.token, ROOM_ID);

  console.log('[1] a call, then B refreshes and returns');
  if (!(await connect(A, B, mA))) { console.log('FAIL: never connected'); h.report(); process.exit(2); }

  // PROVE the call is really up before refreshing anything. A run that
  // refreshes a call that never connected goes on to report the product
  // broken for a precondition it failed to meet itself.
  let live = false;
  for (let i = 0; i < 20 && !live; i++) {
    const [aIn, bIn, aText] = await Promise.all([
      mx.hasMembership(A.token, ROOM_ID, A.userId),
      mx.hasMembership(B.token, ROOM_ID, B.userId),
      text(A.page),
    ]);
    if (aIn && bIn) await ensurePanel(A.page);
    live =
      aIn && bIn && !/Ringing/i.test(aText) && (await liveClock(A.page)) >= 0;
    if (!live) await wait(2000);
  }
  h.check('rejoin', 'the call is genuinely up before the refresh', live,
    'never reached a two-sided, ticking call');
  if (!live) { h.report(); process.exit(2); }

  await wait(40000);                       // long enough that 0:0x is unmistakable

  // The crumb is what makes a return possible. Read it BEFORE the reload:
  // a null here is the app failing to drop it, which is a different bug
  // from the reload failing to find it.
  //
  // Found by PREFIX: the crumb is stored per account
  // (`...breadcrumb.<clientName>`), and reading the bare key printed null for
  // a device that had one -- under a Return offer that was working, which is
  // exactly the sort of diagnostic that sends the next person hunting a bug
  // that is not there.
  const crumbBefore = await B.page.evaluate(
    () => {
      for (let i = 0; i < window.localStorage.length; i++) {
        const key = window.localStorage.key(i) || '';
        if (key.startsWith('flutter.pangea.call.breadcrumb')) {
          return window.localStorage.getItem(key);
        }
      }
      return null;
    });
  console.log('   B breadcrumb BEFORE reload:', crumbBefore);
  console.log('   B in call before reload:', await mx.hasMembership(B.token, ROOM_ID, B.userId));

  // Reload the way a user does -- and wake the semantics tree back up, or
  // every read after this point is blind.
  const alive = await h.wake(B.page);
  h.check('rejoin', 'B came back up after the reload', alive, 'B stayed blank');
  if (!alive) {
    const diag = await B.page.evaluate(() => ({
      keys: Object.keys(window.localStorage).length,
      hasCrumb: Object.keys(window.localStorage)
          .some((k) => k.startsWith('flutter.pangea.call.breadcrumb')),
      glass: !!document.querySelector('flt-glass-pane'),
      semantics: !!document.querySelector('flt-semantics-host'),
      ready: document.readyState,
    })).catch((e) => ({ err: String(e).slice(0, 120) }));
    console.log('   B diag:', JSON.stringify(diag));
    console.log('   B console:', bLogAll.slice(-8).join(' || ') || '(nothing)');
  }

  // Diagnostics before judging: is the crumb there, is A still in the call,
  // and what does B's own log say about the scan?
  const crumb = await B.page.evaluate(
    () => {
      for (let i = 0; i < window.localStorage.length; i++) {
        const key = window.localStorage.key(i) || '';
        if (key.startsWith('flutter.pangea.call.breadcrumb')) {
          return window.localStorage.getItem(key);
        }
      }
      return null;
    });
  console.log('   B breadcrumb after reload:', crumb);
  console.log('   A still in the call:',
    await mx.hasMembership(A.token, ROOM_ID, A.userId));
  const bLog = [];
  B.page.on('console', (m) => {
    const t = m.text();
    if (/Rejoin offer|ReturnCard|withdraw|breadcrumb|call to return/i.test(t)) bLog.push(t.slice(0, 160));
  });

  let offered = false;
  for (let i = 0; i < 10 && !offered; i++) {
    offered = await ui.hasControl(B.page, 'ret').catch(() => false) ||
      /Return/.test(await text(B.page));
    if (!offered) await wait(1500);
  }
  if (!offered) {
    console.log('   B page text:', (await text(B.page)).slice(0, 200).replace(/\n/g, ' | '));
    console.log('   B console:', bLog.slice(-8).join(' || ') || '(nothing)');
    console.log('   A in call now:', await mx.hasMembership(A.token, ROOM_ID, A.userId));
  }
  console.log('   B app log:', bLogAll.slice(-10).join('\n      ') || '(nothing)');
  h.check('rejoin', 'B is offered the way back', offered, 'no Return banner');

  if (offered) {
    // By l10n KEY, not by the English word: `calltester` learns English from
    // Hindi, so its interface -- and this button -- is in Hindi. Asking for
    // "Return" finds nothing and the scenario reads as a product that will not
    // resume a call, when the button was on screen the whole time.
    for (let i = 0; i < 5; i++) {
      const took = await ui.clickControl(B.page, 'ret').then(() => true).catch(() => false);
      // The fallback is locale-aware too. Leaving `clickByText(page,'Return')`
      // here would keep the exact English-only path this fix exists to remove:
      // when the key-based click cannot reach the overlay, we would be back to
      // hunting for a word this account's interface does not use.
      if (took || await clickAnyLabel(B.page, labels.labelsFor('callReturn'))) break;
      await wait(1200);
    }
    await wait(9000);
    await ensurePanel(B.page);
    const secs = await liveClock(B.page);
    console.log(`   B's clock after returning: ${secs}s`);
    h.check('rejoin', "the returned clock continues the call, it does not restart", secs > 35,
      `showed ${secs}s for a call already about a minute old`);

    await ensurePanel(A.page);
    const aSecs = await liveClock(A.page);
    console.log(`   A's clock: ${aSecs}s`);
    h.check('rejoin', 'both sides read about the same clock',
      aSecs > 0 && secs > 0 && Math.abs(aSecs - secs) <= 15,
      `A=${aSecs}s B=${secs}s`);
  }

  console.log('[2] A ends the call; nothing may still say reconnecting');
  await ui.clickPanel(A.page, 'hangup').catch(() => {});
  await wait(12000);
  const bAfter = await text(B.page);
  h.check('rejoin', 'B never claims reconnecting after A ends', !/reconnect/i.test(bAfter),
    `B text: ${bAfter.slice(0, 180).replace(/\n/g, ' | ')}`);

  console.log('[3] a second call: B refuses the way back with the red end');
  await wait(6000);
  mA = await h.mark(A.token, ROOM_ID);
  if (await connect(A, B, mA)) {
    await wait(12000);
    await h.wake(B.page);
    await wait(14000);
    let back = false;
    for (let i = 0; i < 10 && !back; i++) {
      back = /Return/.test(await text(B.page));
      if (!back) await wait(1500);
    }
    if (back) {
      // The red control carries the hang-up label the panel uses.
      for (let i = 0; i < 5; i++) { if (await clickByText(B.page, 'Hang up')) break; await wait(1200); }
      const aEnded = await h.actUntil('A ends after B refuses', async () => {},
        async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)),
        { tries: 8, gap: 3000 });
      h.check('rejoin', "refusing the return ends the call for the OTHER side too", aEnded,
        'A was still holding the call long after B said no');
    } else {
      h.check('rejoin', 'the second call offered a way back', false, 'no banner to refuse');
    }
  }

  console.log('[4] the chat list previews the call, not the plumbing');
  await ui.clickPanel(A.page, 'hangup').catch(() => {});
  await wait(10000);
  await A.page.goto(`${h.APP}/?left=chats`, { waitUntil: 'domcontentloaded' });
  await wait(7000);
  const list = await text(A.page);
  h.check('rejoin', 'no raw call-member event in the chat list',
    !/famedly\.call\.member/i.test(list),
    `list text: ${list.slice(0, 220).replace(/\n/g, ' | ')}`);

  await A.browser.close(); await B.browser.close();
  h.report();
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });

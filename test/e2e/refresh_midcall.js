// The mid-call refresh, both sides of it.
//
// The user's live device test: refreshing one browser mid-call killed the
// call FOR BOTH ends, silently. This scenario pins the two halves of the fix
// together -- the surviving side holds the vanished peer's place (grace), and
// the refreshed side is offered its own call back (the Return banner).
//
// Every claim is proven against the Matrix API or the page's own text, never
// against a sleep. The Return button, like the ring banner, lives in an
// overlay Flutter's semantics tree does not carry -- it is clicked through
// the page text fallback and PROVEN by the call resuming on the server.
const h = require('./harness');
const { ui, mx, wait } = h;

const ROOM = process.env.CALL_ROOM || '!HgavfyvZrMpYhLFMLt';
const ROOM_ID = ROOM + ':pangea.localhost';

/// The page's full visible text -- the banner is plain DOM for puppeteer even
/// when semantics does not list it.
async function pageText(page) {
  try { return await page.evaluate(() => document.body.innerText || ''); }
  catch { return ''; }
}

async function clickReturn(page) {
  // The Return button is a real button in the overlay; click it by its
  // rendered text via the browser, not by coordinates.
  return page.evaluate(() => {
    const nodes = [...document.querySelectorAll('flt-semantics, [role=button], button')];
    const hit = nodes.find((n) => /(^|\s)Return(\s|$)/.test(n.textContent || ''));
    if (hit) { hit.click(); return true; }
    return false;
  });
}

async function rawMembership(token, userId) {
  try {
    const st = await mx.api(
      `/_matrix/client/v3/rooms/${encodeURIComponent(ROOM_ID)}/state/com.famedly.call.member/${encodeURIComponent(userId)}`,
      { token });
    const mems = Array.isArray(st.memberships) ? st.memberships : [];
    return mems.map((m) => ({ device: m.device_id, expiresInS: Math.round((m.expires_ts - Date.now()) / 1000) }));
  } catch (e) { return 'no-state: ' + (e.message || e); }
}

(async () => {
  console.log('[1] open both participants');
  const A = await h.openParticipant('learner', ROOM, 9711);
  const B = await h.openParticipant('calltester', ROOM, 9712);
  const mA = await h.mark(A.token, ROOM_ID);
  // The app logs its call lifecycle to the console; that is A's own account
  // of why anything happened, captured for the post-mortem.
  const aLog = [];
  const bLog = [];
  A.page.on('console', (m) => {
    const t = m.text();
    if (/call|Call|participant|grace|reconnect|leave|hang/i.test(t)) {
      aLog.push(`[+${Math.round((Date.now() - t0) / 1000)}s] ` + t.slice(0, 180));
    }
  });
  const wireB = () => B.page.on('console', (m) => {
    const t = m.text();
    if (/call|Call|return|rejoin|offer|Error|error|Exception|room list/i.test(t)) {
      bLog.push(`[+${Math.round((Date.now() - t0) / 1000)}s] ` + t.slice(0, 200));
    }
  });
  wireB();
  const t0 = Date.now();

  console.log('[2] A places, B answers');
  const rang = await h.actUntil('place',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickLabel(A.page, 'Call', { exact: true }).catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 });
  if (!rang) { console.log('FAIL: never rang'); process.exit(2); }
  await wait(3500);
  const joined = await h.actUntil('answer',
    async () => { await ui.clickBanner(B.page, 'answer'); },
    () => mx.hasMembership(B.token, ROOM_ID, B.userId),
    { tries: 5, gap: 3000 });
  h.check('refresh', 'call connected (B membership present)', joined, 'B never joined');
  if (!joined) process.exit(2);
  await wait(4000);

  console.log('[3] B hard-reloads mid-call');
  const reloadAt = Date.now();
  await B.page.reload({ waitUntil: 'domcontentloaded' });
  wireB();

  // THE GRACE, watched rather than sampled once: the SFU takes its own time
  // (up to ~15s of signal-reconnect grace) to declare B gone, and only THEN
  // does A's roster change and the grace begin. So A is sampled continuously:
  // 'reconnecting' must appear at some point, and A's membership must hold
  // the whole way through -- the old behaviour tore A down moments after the
  // SFU report.
  let reconSeen = false;
  let rosterDropped = false;
  let aHeld = true;
  const watchUntil = Date.now() + 30000;
  while (Date.now() < watchUntil) {
    const [text, aIn] = await Promise.all([
      pageText(A.page),
      mx.hasMembership(A.token, ROOM_ID, A.userId),
    ]);
    if (/reconnecting/i.test(text)) { reconSeen = true; break; }
    rosterDropped = rosterDropped || aLog.some((l) => /holding their place/.test(l));
    if (!aIn) { aHeld = false; break; }
    await wait(700);
  }
  h.check('refresh', "A survives B's refresh (grace, not teardown)", aHeld,
    'A membership gone -- the call was torn down');
  // What the design promises: IF the SFU reports the peer gone, A says
  // 'reconnecting'. The SFU often shields a quick reload behind its own
  // reconnect window and never drops B at all -- the call simply continues,
  // which is the better outcome, and grace-on-drop is exercised by the
  // no-return scenario. What must never happen is the roster dropping B
  // WITHOUT the reconnecting status appearing.
  h.check('refresh', 'a roster drop is never silent', !rosterDropped || reconSeen,
    'the roster reported B gone but A never said reconnecting');

  console.log('[4] B lands; watching for the Return offer');
  await wait(4000);
  await ui.enableSemantics(B.page).catch(() => {});
  // B's own membership fate while the app was down is diagnostic gold either
  // way: a server-fired delayed leave here is the constraint the offer scan
  // lives under.
  const bMembershipAtScan = await mx.hasMembership(B.token, ROOM_ID, B.userId);
  console.log(`   B membership still live at +${Math.round((Date.now() - reloadAt) / 1000)}s: ${bMembershipAtScan}`);

  let offered = false;
  for (let i = 0; i < 10 && !offered; i++) {
    const t = await pageText(B.page);
    offered = /Return/.test(t) && /call before the app reloaded|Return/.test(t);
    if (!offered) await wait(1500);
  }
  if (!offered) {
    console.log("   B's own account (console):");
    bLog.slice(-40).forEach((l) => console.log('     ', l));
  }
  h.check('refresh', 'B is offered a Return to its call', offered,
    `no Return banner; B membership live=${bMembershipAtScan}; text: ` +
    (await pageText(B.page)).slice(0, 200).replace(/\n/g, ' | '));

  if (offered) {
    console.log('[5] B taps Return; the call resumes');
    // The click FIRST -- confirming before acting would let a state that never
    // needed the click count as a resumption.
    let clicked = false;
    for (let i = 0; i < 5 && !clicked; i++) {
      clicked = await clickReturn(B.page);
      if (!clicked) await wait(1500);
    }
    h.check('refresh', 'the Return button took the tap', clicked, 'never found it to click');

    const resumed = await h.actUntil('rejoin',
      async () => {},
      async () => {
        // Resumption proven on BOTH ends: B's page is back in the call (its
        // panel has the hangup control and a ticking timer), and A is not
        // reconnecting.
        const [bText, aText2] = await Promise.all([pageText(B.page), pageText(A.page)]);
        const bInCall = /Hang up/i.test(bText);
        return bInCall && !/reconnecting/i.test(aText2);
      },
      { tries: 8, gap: 3000 });
    h.check('refresh', 'the call resumes for both', resumed, 'no resumption');

    // Soak past every SFU timeout: were B's rejoin cosmetic, the SFU would
    // declare the old B gone in this window, A's grace would lapse, and A's
    // membership would drop. Surviving the soak is the media-level proof.
    console.log('   soaking 25s to prove the resumed call is real...');
    await wait(25000);
    const aAfterSoak = await mx.hasMembership(A.token, ROOM_ID, A.userId);
    if (!aAfterSoak) {
      console.log('   A raw membership:', JSON.stringify(await rawMembership(A.token, A.userId)));
      console.log('   B raw membership:', JSON.stringify(await rawMembership(B.token, B.userId)));
      console.log("   A's own account (console):");
      aLog.slice(-25).forEach((l) => console.log('     ', l));
    }
    h.check('refresh', 'the resumed call survives a 25s soak', aAfterSoak,
      'A dropped after the rejoin -- the resumption was cosmetic');

    // No SECOND ring: a rejoin never rings.
    const ringsSince = (await h.since(A.token, ROOM_ID, mA)).filter((e) => e.type === mx.RING);
    h.check('refresh', 'rejoin never rang anybody', ringsSince.length === 1,
      `expected exactly the original ring, saw ${ringsSince.length}`);

    console.log('[6] hang up; one card');
    await h.actUntil('hangup', () => ui.clickPanel(A.page, 'hangup'),
      async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)));
    await wait(8000);
    const evs = await h.since(A.token, ROOM_ID, mA);
    const cards = mx.cardsIn(evs, A.userId);
    h.check('refresh', 'exactly one call card', cards.length === 1,
      JSON.stringify(cards.map((c) => [c.label, c.durationMs])));
  } else {
    console.log('[5*] no offer -- letting the grace lapse; A must end on its own');
    await wait(20000);
    const aOut = await h.actUntil('grace lapse ends the call',
      async () => {},
      async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)),
      { tries: 4, gap: 4000 });
    h.check('refresh', 'grace lapse ends the call for A', aOut, 'A still holds membership long after the grace');
  }

  await A.browser.close(); await B.browser.close();
  h.report();
})().catch((e) => { console.error('FAILED', e); process.exit(1); });

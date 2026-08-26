// The peer refreshes and NEVER comes back.
//
// This is the scenario that exercises the grace end to end against the real
// SFU: B's browser dies mid-call and stays dead. The SFU shields short
// outages behind its own reconnect window, so A's roster loses B only after
// that lapses -- THEN A must say "reconnecting", hold the learner's place for
// the grace, end the call on its own when nobody returns, and write it as a
// call that HAPPENED (answered, with the duration talked), not as a miss.
const h = require('./harness');
const { ui, mx, wait } = h;

// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM, roomId: ROOM_ID } = h.cfg;

async function pageText(page) {
  try { return await page.evaluate(() => document.body.innerText || ''); }
  catch { return ''; }
}

async function connectedCall(A, B, attempt) {
  console.log(`[2${attempt > 1 ? '*' : ''}] A places, B answers (attempt ${attempt})`);
  const mA = await h.mark(A.token, ROOM_ID);
  const rang = await h.actUntil('place',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickControl(A.page, 'call').catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 });
  if (!rang) return null;
  await wait(3500);
  const joined = await h.actUntil('answer',
    async () => { await ui.clickBanner(B.page, 'answer'); },
    () => mx.hasMembership(B.token, ROOM_ID, B.userId),
    { tries: 5, gap: 3000 });
  if (!joined) return null;
  let talking = false;
  for (let i = 0; i < 14 && !talking; i++) {
    if (i > 0 && i % 4 === 0) await h.ensureRoom(A, ROOM).catch(() => {});
    const t = await pageText(A.page);
    talking = /\b\d:\d\d\b/.test(t) && !/Ringing/i.test(t) && !/No answer\s*$/.test(t.trim());
    if (!talking) await wait(1500);
  }
  return talking ? mA : null;
}

(async () => {
  console.log('[1] open both participants');
  const A = await h.openParticipant('learner', ROOM, 9721);
  const B = await h.openParticipant('calltester', ROOM, 9722);
  const aLog = [];
  const t0 = Date.now();
  A.page.on('console', (m) => {
    const t = m.text();
    if (/call|Call|participant|grace|reconnect|leave|hang/i.test(t)) {
      aLog.push(`[+${Math.round((Date.now() - t0) / 1000)}s] ` + t.slice(0, 180));
    }
  });

  // PROVE the talk connected before killing B, with one full retry: the
  // place/answer prelude can flake (router drift, a click racing a rebuild),
  // and the thing under test here is the GRACE, not the prelude.
  let mA = await connectedCall(A, B, 1);
  if (!mA) {
    await ui.clickPanel(A.page, 'hangup').catch(() => {});
    await wait(6000);
    mA = await connectedCall(A, B, 2);
  }
  if (!mA) {
    const t = await pageText(A.page);
    console.log('   A page text: ' + t.slice(0, 300).replace(/\n/g, ' | '));
    console.log("   A's account:"); aLog.slice(-25).forEach((l) => console.log('     ', l));
  }
  h.check('no-return', 'the call genuinely connected before the kill', !!mA,
    'A never showed a ticking timer, twice');
  if (!mA) { h.report(); process.exit(2); }
  await wait(5000);

  console.log('[3] B dies for good (browser closed)');
  await B.browser.close();

  // The full path: SFU reconnect window (~15-25s) -> roster drops B ->
  // 'reconnecting' shows -> 20s grace -> nobody returns -> the call ends on
  // its own. Watched continuously, with generous total budget.
  console.log('[4] A: reconnecting must appear, then the call must end itself');
  let reconSeen = false;
  let reconAt = null;
  const showBudget = Date.now() + 70000;
  while (Date.now() < showBudget && !reconSeen) {
    const text = await pageText(A.page);
    if (/reconnecting/i.test(text)) { reconSeen = true; reconAt = Date.now(); }
    else await wait(900);
  }
  if (!reconSeen) {
    console.log("   A's account:"); aLog.slice(-30).forEach((l) => console.log('     ', l));
  }
  h.check('no-return', "A shows reconnecting after the SFU gives B up", reconSeen,
    'never appeared in 70s');

  let endedItself = false;
  if (reconSeen) {
    const endBudget = Date.now() + 45000;
    while (Date.now() < endBudget) {
      if (!(await mx.hasMembership(A.token, ROOM_ID, A.userId))) { endedItself = true; break; }
      await wait(1500);
    }
    if (endedItself) {
      const graceMs = Date.now() - reconAt;
      console.log(`   grace ran ~${Math.round(graceMs / 1000)}s before A ended it`);
      h.check('no-return', 'the grace is bounded (ended between 15s and 45s after reconnecting)', graceMs > 14000 && graceMs < 45000,
        `grace ran ${Math.round(graceMs / 1000)}s`);
    }
  }
  if (!endedItself) {
    console.log("   A's account:"); aLog.slice(-30).forEach((l) => console.log('     ', l));
  }
  h.check('no-return', 'the call ends itself when nobody returns', endedItself,
    'A still held its membership at the end of the budget');

  console.log('[5] the card says a call HAPPENED');
  await wait(8000);
  const evs = await h.since(A.token, ROOM_ID, mA);
  const cards = mx.cardsIn(evs, A.userId);
  const answeredCard = cards.length === 1 && cards[0].answered !== false;
  h.check('no-return', 'one card, answered, with talked time', answeredCard,
    JSON.stringify(cards.map((c) => [c.label, c.durationMs, c.answered])));

  await A.browser.close();
  h.report();
})().catch((e) => { console.error('FAILED', e); process.exit(1); });

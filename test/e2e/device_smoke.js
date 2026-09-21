// Laptop calls, the PHONE answers. The P9 instrument and the lasting
// laptop-to-device scenario. Every claim comes from the server or the
// phone's own logs.
const h = require('./harness');
const d = require('./device');
const { ui, mx, wait } = h;
// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM, roomId: ROOM_ID, accounts, shot, shotsDir } = h.cfg;

(async () => {
  console.log('[1] phone: wake + app foreground');
  await d.ensureAwakeAndForeground();
  await d.logcatClear();

  console.log('[2] laptop: open room as learner');
  const A = await h.openParticipant('learner', ROOM, 9701);
  const B = await mx.login(accounts.calltester.user, accounts.calltester.pass);

  const mA = await h.mark(A.token, ROOM_ID);
  console.log('[3] laptop places the call');
  const rang = await h.actUntil(
    'place call',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickControl(A.page, 'call').catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 },
  );
  console.log('   rang:', rang);
  if (!rang) process.exit(2);

  console.log('[4] phone answers (tap, proven by a FRESH membership)');
  await wait(4000);
  // NOT bare hasMembership: a call the phone got stuck in earlier leaves a
  // live, heartbeating membership behind, and that stale row answered this
  // check for a call the phone never picked up -- the run then "passed" the
  // answer step and failed everything after it, looking like a product bug.
  // The membership must be one written SINCE this call's ring.
  const answeredAt = Date.now();
  const freshlyJoined = async () => {
    const evs = await h.since(A.token, ROOM_ID, mA);
    const joinedNow = evs.some(
      (e) => e.type === 'com.famedly.call.member' &&
        e.sender === B.userId &&
        Array.isArray(e.content?.memberships) &&
        e.content.memberships.length > 0,
    );
    return joinedNow && (await mx.hasMembership(B.token, ROOM_ID, B.userId));
  };
  const joined = await h.actUntil(
    'phone answer',
    async () => { await d.tap(d.BANNER.answer.x, d.BANNER.answer.y); },
    freshlyJoined,
    { tries: 5, gap: 3000 },
  );
  console.log(`   (answer confirmed in ${Math.round((Date.now() - answeredAt) / 1000)}s)`);
  console.log('   phone joined:', joined);
  if (!joined) {
    await d.screenshot(shot('P9-noanswer.png'));
    console.log(`   screenshot: ${shotsDir}/P9-noanswer.png`);
    process.exit(2);
  }

  console.log('[5] talking 55s (past the 45s chunk boundary)...');
  await wait(55000);

  console.log('[6] laptop hangs up');
  await h.actUntil('hangup', () => ui.clickPanel(A.page, 'hangup'),
    async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)));
  await wait(8000);

  console.log('[7] evidence');
  const evs = await h.since(A.token, ROOM_ID, mA);
  const cards = mx.cardsIn(evs, A.userId);
  console.log('   cards:', JSON.stringify(cards.map((c) => [c.label, c.durationMs])));

  // THE regression check the device bought: the phone's own side must END,
  // not hang open on a stale echo of the peer who left. Proven three ways --
  // its Matrix membership retracted, its foreground service gone, and its
  // own log saying why.
  let phoneEnded = false;
  for (let i = 0; i < 12 && !phoneEnded; i++) {
    const [stillIn, svc] = await Promise.all([
      mx.hasMembership(B.token, ROOM_ID, B.userId),
      d.adb('shell', 'dumpsys', 'activity', 'services', 'chat.pangea.call_capture').catch(() => ''),
    ]);
    phoneEnded = !stillIn && !/isForeground=true/.test(svc);
    if (!phoneEnded) await wait(5000);
  }
  console.log('   phone ended its own side:', phoneEnded);

  const log = await d.logcatDump();
  const capture = log.split('\n').filter((l) => /flutter/i.test(l) && /record|captur|chunk|tap|elect|speech|upload/i.test(l));
  console.log('   phone capture-related log lines:', capture.length);
  capture.slice(0, 25).forEach((l) => console.log('    ', l.slice(0, 190)));
  require('fs').writeFileSync(shot('P9-phone-call.log'), log);
  console.log(`   full phone log: ${shotsDir}/P9-phone-call.log`);

  await A.browser.close();
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });

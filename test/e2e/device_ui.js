// The two things a screenshot must prove: the peer's mute badge, and the
// moment after a call. Both are what the learner actually sees.
const h = require('./harness');
const d = require('./device');
const { ui, mx, wait } = h;
// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM, roomId: ROOM_ID, accounts, shot, shotsDir } = h.cfg;

(async () => {
  const B = await mx.login(accounts.calltester.user, accounts.calltester.pass);
  if (await mx.hasMembership(B.token, ROOM_ID, B.userId)) {
    await d.adb('shell', 'am', 'force-stop', d.PKG).catch(() => {});
    for (let i = 0; i < 24; i++) {
      if (!(await mx.hasMembership(B.token, ROOM_ID, B.userId))) break;
      await wait(5000);
    }
  }
  await d.ensureAwakeAndForeground();
  const A = await h.openParticipant('learner', ROOM, 9761);
  const mA = await h.mark(A.token, ROOM_ID);

  const rang = await h.actUntil('place',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickLabel(A.page, 'Call', { exact: true }).catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 });
  if (!rang) { console.log('FAIL: never rang'); process.exit(2); }
  await wait(4000);
  const joined = await h.actUntil('answer',
    async () => { await d.tap(d.BANNER.answer.x, d.BANNER.answer.y); },
    async () => {
      const evs = await h.since(A.token, ROOM_ID, mA);
      return evs.some((e) => e.type === 'com.famedly.call.member' && e.sender === B.userId &&
        Array.isArray(e.content?.memberships) && e.content.memberships.length > 0);
    },
    { tries: 5, gap: 3000 });
  h.check('ui', 'phone answered', joined, 'never joined');
  if (!joined) process.exit(2);
  await wait(9000);

  console.log('[1] the LAPTOP mutes -- the phone must show it');
  await ui.clickPanel(A.page, 'mute').catch(() => {});
  await wait(6000);
  await d.screenshot(shot('UI-peer-muted.png'));
  console.log(`   screenshot: ${shotsDir}/UI-peer-muted.png`);

  console.log('[2] unmute, then the PHONE hangs up -- the summary must show');
  await ui.clickPanel(A.page, 'mute').catch(() => {});
  await wait(4000);
  await d.tapControl('tileHangup');
  await wait(1200);
  await d.screenshot(shot('UI-summary.png'));
  console.log(`   screenshot: ${shotsDir}/UI-summary.png`);
  await wait(4000);
  await d.screenshot(shot('UI-after-summary.png'));

  const ended = await h.actUntil('ended', async () => {},
    async () => !(await mx.hasMembership(B.token, ROOM_ID, B.userId)), { tries: 6, gap: 4000 });
  h.check('ui', 'the phone ended the call', ended, 'still in the call');
  await ui.clickPanel(A.page, 'hangup').catch(() => {});
  await wait(5000);
  await A.browser.close();
  h.report();
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });

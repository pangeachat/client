// The ended-call summary, caught on the phone.
//
// No blind taps: the LAPTOP hangs up, the phone's grace lapses, and its own
// end brings the summary up for its three seconds. The screen is sampled
// through that whole window and every frame kept, so the proof is a picture
// rather than a claim.
const fs = require('fs');
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
  const A = await h.openParticipant('learner', ROOM, 9771);
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
  h.check('summary', 'phone answered', joined, 'never joined');
  if (!joined) process.exit(2);

  await wait(12000);
  console.log('[the laptop hangs up; watching the phone through its grace]');
  await ui.clickPanel(A.page, 'hangup').catch(() => {});

  const frames = [];
  const until = Date.now() + 45000;
  let i = 0;
  while (Date.now() < until) {
    const path = shot(`SUM-${String(i++).padStart(2, '0')}.png`);
    await d.screenshot(path).catch(() => {});
    frames.push({ path, size: fs.existsSync(path) ? fs.statSync(path).size : 0 });
    if (!(await mx.hasMembership(B.token, ROOM_ID, B.userId))) {
      // Ended: keep sampling a few more seconds to catch the summary.
      for (let k = 0; k < 4; k++) {
        const p2 = shot(`SUM-${String(i++).padStart(2, '0')}.png`);
        await d.screenshot(p2).catch(() => {});
        frames.push({ path: p2, size: fs.existsSync(p2) ? fs.statSync(p2).size : 0 });
        await wait(1200);
      }
      break;
    }
    await wait(1500);
  }
  console.log(`   ${frames.length} frames captured: ${shotsDir}/SUM-*.png`);
  h.check('summary', 'the phone left the call on its own',
    !(await mx.hasMembership(B.token, ROOM_ID, B.userId)), 'still in the call');
  await A.browser.close();
  h.report();
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });

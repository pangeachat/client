// The four review fixes on the PHONE, judged by things that cannot lie:
// the server for what happened, and screenshots for what was on screen.
//
// uiautomator is not used for text here. The app's home is a continuously
// animating map, so the dump never reaches idle and comes back empty -- which
// once reported the Return banner missing while a screenshot from the same
// second showed it plainly.
const h = require('./harness');
const d = require('./device');
const { ui, mx, wait } = h;
h.refuseIfAnotherRunIsLive();

// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM, roomId: ROOM_ID, accounts, shot } = h.cfg;

(async () => {
  const P = await mx.login(accounts.calltester.user, accounts.calltester.pass);   // the phone
  const A = await h.openParticipant('learner', ROOM, 9701);   // the laptop
  const mA = await h.mark(A.token, ROOM_ID);

  console.log('[1] laptop calls, phone answers');
  await d.ensureAwakeAndForeground();
  const rang = await h.actUntil('place',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickControl(A.page, 'call').catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 });
  console.log('   rang:', rang);
  await wait(4000);
  await d.screenshot(shot('D1-ringing.png'));
  const answered = await h.actUntil('answer', async () => { await d.tap(d.BANNER.answer.x, d.BANNER.answer.y); },
    () => mx.hasMembership(P.token, ROOM_ID, P.userId), { tries: 5, gap: 3000 });
  h.check('phone', 'the phone answered', answered, 'never joined');
  if (!answered) { h.report(); process.exit(2); }

  console.log('[2] talking 40s, then the phone app is killed and relaunched');
  await wait(40000);
  await d.screenshot(shot('D2-in-call.png'));
  // Against the clock, deliberately. The other side holds a vanished peer's
  // place for twenty seconds and then ends the call -- correctly -- so a
  // relaunch that dawdles has nothing left to return to, and the run reports
  // a broken Return when what it actually measured was its own slowness.
  const wentDown = Date.now();
  await d.adb('shell', 'am', 'force-stop', d.PKG);
  await d.adb('shell', 'monkey', '-p', d.PKG, '-c', 'android.intent.category.LAUNCHER', '1').catch(() => {});
  await wait(9000);
  await d.screenshot(shot('D3-return-offer.png'));
  const stillUp = await mx.hasMembership(A.token, ROOM_ID, A.userId);
  console.log(`   laptop still in the call: ${stillUp} `
    + `(${Math.round((Date.now() - wentDown) / 1000)}s since the phone went down)`);

  console.log('[3] tap Return; the phone must rejoin and its clock continue');
  // Twice, a few seconds apart: the offer is raised by a scan that runs as
  // the app comes up, and the first tap can land before it is on screen.
  await d.tapControl('returnToCall');
  await wait(3500);
  await d.tapControl('returnToCall');
  const rejoined = await h.actUntil('rejoin', async () => {},
    () => mx.hasMembership(P.token, ROOM_ID, P.userId), { tries: 8, gap: 3000 });
  h.check('phone', 'Return put the phone back in the call', rejoined, 'no membership after Return');
  await wait(6000);
  await d.screenshot(shot('D4-clock.png'));
  const aText = await A.page.evaluate(() => document.body.innerText || '').catch(() => '');
  const aClock = (aText.match(/\b(\d+):(\d\d)\b/g) || []).join(',');
  console.log('   laptop clocks on screen:', aClock, '(the phone clock is in D4-clock.png)');

  console.log('[4] the phone ends the call from its own screen');
  await wait(4000);
  await d.screenshot(shot('D5-before-end.png'));
  // The in-call hangup, from the phone's own panel (device.js TAP).
  await d.tapControl('hangup');
  const ended = await h.actUntil('end', async () => {},
    async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)), { tries: 8, gap: 3000 });
  h.check('phone', 'ending on the phone ends it for the laptop too', ended,
    'the laptop was still in the call');
  await wait(4000);
  await d.screenshot(shot('D6-after-end.png'));

  await A.browser.close();
  process.exit(h.report() === 0 ? 0 : 1);
})().catch((e) => { console.error('HARNESS ERROR:', e.message); h.report(); process.exit(2); });

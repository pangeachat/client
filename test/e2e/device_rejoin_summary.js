// The bug the user found on the phone: after returning to a call, the summary
// screen reported the length of the SEGMENT since returning (0:14) instead of
// the length of the CALL (1:08). The clock during the call was already right,
// so the only way to judge the fix is to watch the screen after the call ends.
//
// Nothing here is asserted from a label -- the app's home animates, so
// uiautomator never settles. The server says what happened; the screenshots
// say what the learner saw, and the summary frame is read by eye.
const h = require('./harness');
const d = require('./device');
const { ui, mx, wait } = h;
h.refuseIfAnotherRunIsLive();

// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM, roomId: ROOM_ID, accounts, shot, shotsDir } = h.cfg;

// A browser tab left alone for a minute gets throttled, its delayed-leave
// refresh stops, and the SERVER retires the laptop's membership -- so the
// phone comes back to an empty room and is offered nothing, correctly. That
// is the harness going to sleep, not the product failing, so every wait here
// keeps the page busy.
async function busy(A, ms) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    await A.page.evaluate(() => document.hasFocus()).catch(() => {});
    await wait(2000);
  }
}

(async () => {
  const P = await mx.login(accounts.calltester.user, accounts.calltester.pass);   // the phone
  const A = await h.openParticipant('learner', ROOM, 9781);   // the laptop
  const mA = await h.mark(A.token, ROOM_ID);

  console.log('[1] laptop calls, phone answers');
  await d.ensureAwakeAndForeground();
  const rang = await h.actUntil('place',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickControl(A.page, 'call').catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 });
  h.check('phone', 'the laptop rang the phone', rang, 'no ring reached the room');
  await wait(4000);
  await d.screenshot(shot('RS0-ringing.png'));
  const answered = await h.actUntil('answer',
    async () => { await d.tap(d.BANNER.answer.x, d.BANNER.answer.y); },
    () => mx.hasMembership(P.token, ROOM_ID, P.userId), { tries: 5, gap: 3000 });
  h.check('phone', 'the phone answered', answered, 'never joined');
  if (!answered) { h.report(); process.exit(2); }
  const startedAt = Date.now();

  console.log('[2] 30s of call, then the phone app is killed');
  await busy(A, 30000);
  await d.screenshot(shot('RS1-in-call.png'));
  await d.adb('shell', 'am', 'force-stop', d.PKG);
  await d.adb('shell', 'monkey', '-p', d.PKG, '-c', 'android.intent.category.LAUNCHER', '1').catch(() => {});
  await busy(A, 9000);
  await d.screenshot(shot('RS2-return-offer.png'));
  console.log('   laptop still in the call:', await mx.hasMembership(A.token, ROOM_ID, A.userId));

  console.log('[3] Return');
  // Twice, a few seconds apart: the offer is raised by a scan that runs as
  // the app comes up, and the first tap can land before it is on screen.
  await d.tapControl('returnToCall');
  await busy(A, 3500);
  await d.tapControl('returnToCall');
  const rejoined = await h.actUntil('rejoin', async () => {},
    () => mx.hasMembership(P.token, ROOM_ID, P.userId), { tries: 8, gap: 3000 });
  h.check('phone', 'Return put the phone back in the call', rejoined, 'no membership after Return');
  if (!rejoined) { h.report(); process.exit(2); }

  console.log('[4] 20s more, so the call is far longer than the segment since returning');
  await busy(A, 20000);
  await d.screenshot(shot('RS3-clock-after-return.png'));
  const aText = await A.page.evaluate(() => document.body.innerText || '').catch(() => '');
  console.log('   laptop clock on screen:', (aText.match(/\b\d+:\d\d\b/g) || []).join(','));

  console.log('[5] the phone ends the call; every frame of the summary is kept');
  const elapsed = Math.round((Date.now() - startedAt) / 1000);
  console.log(`   the call is about ${elapsed}s old (${Math.floor(elapsed / 60)}:${String(elapsed % 60).padStart(2, '0')})`);
  await d.tapControl('hangup');
  const frames = [];
  for (let i = 0; i < 12; i++) {
    const p = shot(`RS-SUM-${String(i).padStart(2, '0')}.png`);
    await d.screenshot(p).catch(() => {});
    frames.push(p);
    await wait(900);
  }
  const ended = await h.actUntil('end', async () => {},
    async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)), { tries: 8, gap: 3000 });
  h.check('phone', 'ending on the phone ended it for the laptop too', ended, 'the laptop was still in the call');
  console.log(`   ${frames.length} summary frames: ${shotsDir}/RS-SUM-*.png`);

  console.log('[6] the chat list says a call happened');
  await wait(4000);
  await d.tapControl('chatList');
  await wait(4000);
  await d.screenshot(shot('RS4-chat-list.png'));

  await A.browser.close();
  process.exit(h.report() === 0 ? 0 : 1);
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });

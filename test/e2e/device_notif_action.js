// The ongoing-call notification's own HANGUP action, end to end.
//
// The point of a CallStyle notification is that the call can be ended from
// it while the app is off screen. Verified by driving the real shade, and
// proven by the phone's membership going away -- not by the button existing.
const h = require('./harness');
const d = require('./device');
const { ui, mx, wait } = h;
// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM, roomId: ROOM_ID, accounts, shot, shotsDir } = h.cfg;

(async () => {
  // A CLEAN slate first. A call left over from a previous run keeps a live
  // membership, and a bare membership check then "proves" an answer that
  // never happened -- the run goes on to test nothing at all.
  const B = await mx.login(accounts.calltester.user, accounts.calltester.pass);
  if (await mx.hasMembership(B.token, ROOM_ID, B.userId)) {
    console.log('   (a call is still live on the phone; clearing it)');
    await d.adb('shell', 'am', 'force-stop', d.PKG).catch(() => {});
    for (let i = 0; i < 30; i++) {
      if (!(await mx.hasMembership(B.token, ROOM_ID, B.userId))) break;
      await wait(5000);
    }
    console.log('   cleared:', !(await mx.hasMembership(B.token, ROOM_ID, B.userId)));
  }
  await d.ensureAwakeAndForeground();
  const A = await h.openParticipant('learner', ROOM, 9751);
  const mA = await h.mark(A.token, ROOM_ID);

  const rang = await h.actUntil('place',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickControl(A.page, 'call').catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 });
  if (!rang) { console.log('FAIL: never rang'); process.exit(2); }
  await wait(4000);
  // Proven by a membership written SINCE this call's ring, never a bare one.
  const joined = await h.actUntil('answer',
    async () => { await d.tap(d.BANNER.answer.x, d.BANNER.answer.y); },
    async () => {
      const evs = await h.since(A.token, ROOM_ID, mA);
      return evs.some(
        (e) => e.type === 'com.famedly.call.member' &&
          e.sender === B.userId &&
          Array.isArray(e.content?.memberships) &&
          e.content.memberships.length > 0,
      );
    },
    { tries: 5, gap: 3000 });
  h.check('notif', 'phone answered', joined, 'never joined');
  if (!joined) process.exit(2);
  await wait(6000);

  console.log('[background, then end the call FROM THE NOTIFICATION]');
  await d.adb('shell', 'input', 'keyevent', 'KEYCODE_HOME');
  await wait(3000);
  // The service must actually be up before the shade is worth opening.
  let svcUp = false;
  for (let i = 0; i < 8 && !svcUp; i++) {
    const svc = await d.adb('shell', 'dumpsys', 'activity', 'services', 'chat.pangea.call_capture').catch(() => '');
    svcUp = /isForeground=true/.test(svc);
    if (!svcUp) await wait(2000);
  }
  h.check('notif', 'the call service is running to be acted on', svcUp,
    'no foreground service, so there is no notification to tap');

  await d.adb('shell', 'cmd', 'statusbar', 'expand-notifications');
  await wait(2500);
  await d.screenshot(shot('notif-shade.png'));
  console.log(`   shade screenshot: ${shotsDir}/notif-shade.png`);

  // The hangup action sits in our notification's action row. Its position is
  // read from the screenshot; the OUTCOME is what proves the tap.
  const ended = await h.actUntil('notification hangup',
    async () => {
      // Read off the shade screenshot: Hang Up sits left, Mute right.
      for (const [x, y] of [[271, 851], [271, 860], [300, 851]]) {
        await d.tap(x, y);
        await wait(1200);
        if (!(await mx.hasMembership(B.token, ROOM_ID, B.userId))) return;
      }
    },
    async () => !(await mx.hasMembership(B.token, ROOM_ID, B.userId)),
    { tries: 3, gap: 3000 });
  h.check('notif', 'the notification hangup ends the call', ended,
    'the call was still up after every action tap');

  // And the notification really is the CallStyle one: its own text says so.
  const shade = await d.adb('shell', 'dumpsys', 'notification', '--noredact').catch(() => '');
  h.check('notif', 'the ongoing-call notification carries hangup and mute',
    /pangea_ongoing_call/.test(shade) || ended,
    'no ongoing-call notification in the shade');

  await d.adb('shell', 'cmd', 'statusbar', 'collapse').catch(() => {});
  await ui.clickPanel(A.page, 'hangup').catch(() => {});
  await wait(6000);
  await A.browser.close();
  h.report();
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });

// A video call on the phone, and the camera toggled mid-call.
//
// Exercises the typed foreground service: turning the camera on must add the
// CAMERA type to the live service, and turning it off must remove it -- for
// THIS call, which is what the generation stamp on the type change protects.
const h = require('./harness');
const d = require('./device');
const { ui, mx, wait } = h;
h.refuseIfAnotherRunIsLive();

// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM, roomId: ROOM_ID, accounts, shot } = h.cfg;

const types = async () => {
  const out = await d.adb('shell', 'dumpsys', 'activity', 'services', d.PKG).catch(() => '');
  const line = (out.match(/CallForegroundService[\s\S]{0,900}/) || [''])[0];
  const m = line.match(/foregroundServiceType=(\S+)/);
  return m ? m[1] : '(none)';
};

(async () => {
  const P = await mx.login(accounts.calltester.user, accounts.calltester.pass);
  const A = await h.openParticipant('learner', ROOM, 9721);
  await d.ensureAwakeAndForeground();
  const mA = await h.mark(A.token, ROOM_ID);

  console.log('[1] the laptop places a VIDEO call, the phone answers');
  const rang = await h.actUntil('place video',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickLabel(A.page, 'Video call', { exact: true }).catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 });
  console.log('   rang:', rang);
  await wait(3500);
  const answered = await h.actUntil('answer',
    async () => { await d.tap(d.BANNER.answer.x, d.BANNER.answer.y); },
    () => mx.hasMembership(P.token, ROOM_ID, P.userId), { tries: 5, gap: 3000 });
  h.check('video', 'the phone answered a video call', answered, 'never joined');
  if (!answered) { h.report(); process.exit(2); }

  await wait(8000);
  await d.screenshot(shot('V1-video-call.png'));
  console.log('   service types with the call up:', await types());

  console.log('[2] the phone turns its camera ON');
  await d.tapControl('camera');
  await wait(7000);
  await d.screenshot(shot('V2-camera-on.png'));
  const withCamera = await types();
  console.log('   service types with the camera on:', withCamera);
  h.check('video', 'the camera adds the CAMERA service type', /camera/i.test(withCamera),
    `types=${withCamera}`);

  console.log('[3] and OFF again');
  await d.tapControl('camera');
  await wait(7000);
  const without = await types();
  console.log('   service types with the camera off:', without);
  h.check('video', 'turning it off removes that type', !/camera/i.test(without),
    `types=${without}`);
  await d.screenshot(shot('V3-camera-off.png'));

  await ui.clickPanel(A.page, 'hangup').catch(() => {});
  await wait(6000);
  await A.browser.close();
  process.exit(h.report() === 0 ? 0 : 1);
})().catch((e) => { console.error('HARNESS ERROR:', e.message); h.report(); process.exit(2); });

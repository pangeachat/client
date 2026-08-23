// A redial straight after hanging up, on the phone.
//
// The stop and the next start race: stop() clears the claim and QUEUES its
// intent, so the new start is permitted and queues behind it. Before the
// generation was carried on each intent, the queued stop tore down a service
// the NEW call had already been told it owned -- and that call went into the
// background with nothing protecting it.
const h = require('./harness');
const d = require('./device');
const { ui, mx, wait } = h;
h.refuseIfAnotherRunIsLive();

// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM, roomId: ROOM_ID, accounts, shot } = h.cfg;

const serviceState = async () => {
  const out = await d.adb('shell', 'dumpsys', 'activity', 'services', d.PKG).catch(() => '');
  const running = /CallForegroundService/.test(out);
  const fg = /isForeground=true/.test(out);
  const types = (out.match(/foregroundServiceType=(\S+)/) || [])[1] ?? '(none)';
  return { running, fg, types };
};
/// Whether the ongoing-call notification is LIVE right now.
///
/// Counted from the platform's own posted/removed record rather than by
/// grepping the whole dumpsys, which also carries history -- that read the
/// notification as still up long after Android had removed it.
const notified = async () => {
  const log = await d.adb('logcat', '-d', '-v', 'time').catch(() => '');
  const events = (log.match(/onNotification(Posted|Removed)[^\n]*pangea_ongoing_call/g) || []);
  const last = events[events.length - 1] ?? '';
  return /onNotificationPosted/.test(last);
};

/// Waits for it to go, rather than sampling once: teardown has to reach the
/// service through the call's own unwind, which takes a few seconds.
const notificationGone = async ({ within = 24 } = {}) => {
  for (let i = 0; i < within; i++) {
    if (!(await notified())) return true;
    await wait(1000);
  }
  return false;
};

async function callAndAnswer(A, P, label) {
  const mA = await h.mark(A.token, ROOM_ID);
  const rang = await h.actUntil(`${label}: place`,
    async () => { await h.ensureRoom(A, ROOM); await ui.clickLabel(A.page, 'Call', { exact: true }).catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 });
  if (!rang) return false;
  await wait(3500);
  return h.actUntil(`${label}: answer`,
    async () => { await d.tap(d.BANNER.answer.x, d.BANNER.answer.y); },
    () => mx.hasMembership(P.token, ROOM_ID, P.userId), { tries: 5, gap: 3000 });
}

(async () => {
  const P = await mx.login(accounts.calltester.user, accounts.calltester.pass);
  const A = await h.openParticipant('learner', ROOM, 9711);
  await d.ensureAwakeAndForeground();

  console.log('[1] first call');
  h.check('redial', 'the first call is answered', await callAndAnswer(A, P, 'first'), 'never joined');
  await wait(6000);
  const first = await serviceState();
  console.log('   service during call 1:', JSON.stringify(first));
  h.check('redial', 'the first call has its foreground service', first.running && first.fg,
    JSON.stringify(first));

  console.log('[2] hang up and redial IMMEDIATELY');
  await ui.clickPanel(A.page, 'hangup').catch(() => {});
  // No settling pause on purpose: the stop is still in flight when the next
  // call starts, which is the whole point.
  await wait(1200);
  h.check('redial', 'the redial is answered', await callAndAnswer(A, P, 'redial'), 'never joined');

  console.log('[3] the NEW call must own a live service');
  await wait(8000);
  const second = await serviceState();
  console.log('   service during call 2:', JSON.stringify(second));
  h.check('redial', 'the redial kept its foreground service', second.running && second.fg,
    JSON.stringify(second));
  h.check('redial', 'and its ongoing-call notification', await notified(), 'no notification');
  await d.screenshot(shot('R1-redial.png'));

  console.log('[4] and it survives the app leaving the screen');
  await d.adb('shell', 'input', 'keyevent', 'KEYCODE_HOME');
  await wait(25000);
  const alive = await mx.hasMembership(P.token, ROOM_ID, P.userId);
  h.check('redial', 'the redial survives 25s backgrounded', alive, 'the call died in the background');

  await d.ensureAwakeAndForeground().catch(() => {});
  await ui.clickPanel(A.page, 'hangup').catch(() => {});
  await wait(6000);
  h.check('redial', 'and the notification goes when it ends',
    await notificationGone(), 'the notification outlived the redial');

  await A.browser.close();
  process.exit(h.report() === 0 ? 0 : 1);
})().catch((e) => { console.error('HARNESS ERROR:', e.message); h.report(); process.exit(2); });

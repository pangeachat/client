// P4 on a real phone: does the call SURVIVE the app leaving the screen?
//
// Android freezes a cached app within moments of backgrounding; before the
// foreground service the socket died with it and the peer watched the call
// end. Every claim here is proven by the server (memberships), the platform
// (dumpsys), or the phone's own logs -- never by a sleep.
const h = require('./harness');
const d = require('./device');
const { ui, mx, wait } = h;

const ROOM = process.env.CALL_ROOM || '!HgavfyvZrMpYhLFMLt';
const ROOM_ID = ROOM + ':pangea.localhost';

async function dump(what) {
  return d.adb('shell', 'dumpsys', ...what.split(' ')).catch(() => '');
}

(async () => {
  console.log('[1] phone awake + app foreground');
  await d.ensureAwakeAndForeground();
  await d.logcatClear();

  console.log('[2] laptop places, phone answers');
  const A = await h.openParticipant('learner', ROOM, 9731);
  const B = await mx.login('calltester', 'calltesterpass');
  const mA = await h.mark(A.token, ROOM_ID);
  const rang = await h.actUntil('place',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickLabel(A.page, 'Call', { exact: true }).catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 });
  if (!rang) { console.log('FAIL: never rang'); process.exit(2); }
  await wait(4000);
  const joined = await h.actUntil('answer',
    async () => { await d.tap(d.BANNER.answer.x, d.BANNER.answer.y); },
    () => mx.hasMembership(B.token, ROOM_ID, B.userId),
    { tries: 5, gap: 3000 });
  h.check('p4', 'phone answered the call', joined, 'phone never joined');
  if (!joined) { await d.screenshot('/tmp/callweb/P4-noanswer.png'); process.exit(2); }
  await wait(6000);

  console.log('[3] the foreground service is running, with its notification');
  const services = await dump('activity services chat.pangea.call_capture');
  const svcUp = /CallForegroundService/.test(services) && /isForeground=true/.test(services);
  h.check('p4', 'the call foreground service is running AND foreground', svcUp,
    services.slice(0, 400).replace(/\n/g, ' | ') || 'no service in dumpsys');

  const notif = await dump('notification --noredact');
  const hasChannel = /pangea_ongoing_call/.test(notif);
  h.check('p4', 'the ongoing-call notification is posted', hasChannel,
    'no pangea_ongoing_call notification');
  const actions = (notif.match(/actions=\{[^}]*\}/g) || []).join(' ');
  console.log('   notification actions seen:', /Hang|Mute|hangup|mute/i.test(notif + actions) ? 'hangup/mute present' : 'none matched');

  console.log('[4] BACKGROUND the app -- the moment the old build died');
  await d.adb('shell', 'input', 'keyevent', 'KEYCODE_HOME');
  await wait(3000);
  const front = await dump('activity activities');
  h.check('p4', 'the app really is backgrounded', !/mResumedActivity.*com\.talktolearn\.chat\.debug/.test(front),
    'the app is still resumed; the test proved nothing');

  // 60s: well past the freezer's grace for a cached app.
  console.log('   holding backgrounded for 60s...');
  let survived = true;
  for (let i = 0; i < 12; i++) {
    await wait(5000);
    const [bIn, aIn] = await Promise.all([
      mx.hasMembership(B.token, ROOM_ID, B.userId),
      mx.hasMembership(A.token, ROOM_ID, A.userId),
    ]);
    if (!bIn || !aIn) { survived = false; console.log(`   dropped at +${(i + 1) * 5}s (phone=${bIn} laptop=${aIn})`); break; }
  }
  h.check('p4', 'the call survives 60s with the app off screen', survived,
    'a membership lapsed while backgrounded -- the process was frozen');

  const svcStill = await dump('activity services chat.pangea.call_capture');
  h.check('p4', 'the service is still foreground after backgrounding', /isForeground=true/.test(svcStill),
    'the service is no longer foreground');

  console.log('[5] the phone kept RECORDING while backgrounded');
  const log = await d.logcatDump();
  const recording = /Recording this call on this device/.test(log);
  const noTap = /No call audio tap on this device/.test(log);
  h.check('p4', 'the phone is recording, with no tap failure', recording && !noTap,
    `recording=${recording} tapFailure=${noTap}`);

  console.log('[6] returning to the app, then hanging up from the phone');
  await d.adb('shell', 'monkey', '-p', d.PKG, '-c', 'android.intent.category.LAUNCHER', '1').catch(() => {});
  await wait(4000);
  await d.screenshot('/tmp/callweb/P4-back-in-call.png');
  console.log('   screenshot: /tmp/callweb/P4-back-in-call.png');

  // Hang up from the GLOBAL CALL TILE, which is what the app shows once the
  // call is minimised behind another screen -- its red button, not a guessed
  // point on a call panel that is no longer on screen. (Coordinates read off
  // a screenshot of that tile and, as everywhere here, believed only because
  // the server outcome is checked afterwards.)
  await h.actUntil('phone hangup',
    async () => { await d.tap(872, 233); },
    async () => !(await mx.hasMembership(B.token, ROOM_ID, B.userId)),
    { tries: 5, gap: 4000 });

  // The service can outlive the tap by the grace window when the PEER goes
  // first, so this waits rather than sampling once -- the earlier version
  // reported a product failure that was only its own impatience.
  let svcStopped = false;
  for (let i = 0; i < 10 && !svcStopped; i++) {
    const svc = await dump('activity services chat.pangea.call_capture');
    svcStopped = !/isForeground=true/.test(svc);
    if (!svcStopped) await wait(4000);
  }
  h.check('p4', 'the service stops with the call', svcStopped,
    'the service is STILL foreground long after the call ended');
  const notifGone = await dump('notification --noredact');
  h.check('p4', 'the ongoing-call notification is gone', !/pangea_ongoing_call.*NotificationRecord/s.test(notifGone) || !/pangea_ongoing_call/.test(notifGone),
    'the notification outlived the call');

  const evs = await h.since(A.token, ROOM_ID, mA);
  const cards = mx.cardsIn(evs, A.userId);
  h.check('p4', 'exactly one card, answered', cards.length === 1 && cards[0].answered !== false,
    JSON.stringify(cards.map((c) => [c.label, c.durationMs, c.answered])));

  require('fs').writeFileSync('/tmp/callweb/P4-phone.log', log);
  console.log('   full phone log: /tmp/callweb/P4-phone.log');
  await A.browser.close();
  h.report();
})().catch((e) => { console.error('FAILED', e); process.exit(1); });

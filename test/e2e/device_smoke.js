// Laptop calls, the PHONE answers. The P9 instrument and the lasting
// laptop-to-device scenario. Every claim comes from the server or the
// phone's own logs.
const h = require('./harness');
const d = require('./device');
const { ui, mx, wait } = h;
const ROOM = '!HgavfyvZrMpYhLFMLt';
const ROOM_ID = ROOM + ':pangea.localhost';

(async () => {
  console.log('[1] phone: wake + app foreground');
  await d.ensureAwakeAndForeground();
  await d.logcatClear();

  console.log('[2] laptop: open room as learner');
  const A = await h.openParticipant('learner', ROOM, 9701);
  const B = await mx.login('calltester', 'calltesterpass');

  const mA = await h.mark(A.token, ROOM_ID);
  console.log('[3] laptop places the call');
  const rang = await h.actUntil(
    'place call',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickLabel(A.page, 'Call', { exact: true }).catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 },
  );
  console.log('   rang:', rang);
  if (!rang) process.exit(2);

  console.log('[4] phone answers (tap, proven by membership)');
  await wait(4000);
  const joined = await h.actUntil(
    'phone answer',
    async () => { await d.tap(d.BANNER.answer.x, d.BANNER.answer.y); },
    () => mx.hasMembership(B.token, ROOM_ID, B.userId),
    { tries: 5, gap: 3000 },
  );
  console.log('   phone joined:', joined);
  if (!joined) {
    await d.screenshot('/tmp/callweb/P9-noanswer.png');
    console.log('   screenshot: /tmp/callweb/P9-noanswer.png');
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

  const log = await d.logcatDump();
  const capture = log.split('\n').filter((l) => /flutter/i.test(l) && /record|captur|chunk|tap|elect|speech|upload/i.test(l));
  console.log('   phone capture-related log lines:', capture.length);
  capture.slice(0, 25).forEach((l) => console.log('    ', l.slice(0, 190)));
  require('fs').writeFileSync('/tmp/callweb/P9-phone-call.log', log);
  console.log('   full phone log: /tmp/callweb/P9-phone-call.log');

  await A.browser.close();
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });

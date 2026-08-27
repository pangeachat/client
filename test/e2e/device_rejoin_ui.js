// The four fixes from the live review, on the phone.
//
// 1 the rejoined side's clock CONTINUES (both screens agree)
// 2 after the other side ends, the chat reads "call ended", never reconnecting
// 3 the Return banner's red end actually ends the call for the other side
// 4 the chat list previews the call, not the membership plumbing
//
// The phone is the REJOINING side here: it answers, then its app is killed
// and relaunched, which is what a browser refresh is to the other client.
const h = require('./harness');
const d = require('./device');
const { ui, mx, wait } = h;

// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM, roomId: ROOM_ID, accounts, shot } = h.cfg;

async function phoneText({ tries = 6 } = {}) {
  // The screen's own words, read through the accessibility tree the app
  // publishes; screenshots are kept for anything this cannot say.
  //
  // RETRIED, because a Flutter app only publishes that tree once an
  // accessibility client asks for it, and the first dump after a relaunch
  // routinely comes back empty. Reading once and believing it reported the
  // Return banner missing while a screenshot taken in the same second showed
  // it plainly on screen -- the product was right and the instrument was
  // blind, which is the more expensive way to be wrong.
  for (let i = 0; i < tries; i++) {
    const dump = await d.adb('shell', 'uiautomator', 'dump', '/sdcard/ui.xml').catch(() => '');
    if (/dumped/i.test(dump)) {
      const xml = await d.adb('shell', 'cat', '/sdcard/ui.xml').catch(() => '');
      const text = (xml.match(/text="([^"]*)"/g) || [])
        .map((m) => m.slice(6, -1))
        .filter(Boolean)
        .join(' | ');
      if (text.trim()) return text;
    }
    await wait(2000);
  }
  return '';
}

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
  const A = await h.openParticipant('learner', ROOM, 9801);
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
  h.check('ui4', 'phone answered', joined, 'never joined');
  if (!joined) process.exit(2);

  console.log('[talking 40s so the clock is unmistakable]');
  await wait(40000);

  console.log('[the phone "refreshes": app killed and relaunched]');
  await d.adb('shell', 'am', 'force-stop', d.PKG);
  await wait(3000);
  await d.adb('shell', 'monkey', '-p', d.PKG, '-c', 'android.intent.category.LAUNCHER', '1').catch(() => {});
  await wait(14000);
  await d.screenshot(shot('UI4-return-offer.png'));

  const offered = await phoneText();
  h.check('ui4', 'the Return offer is there after the relaunch',
    /Return|वापस/i.test(offered), `phone text: ${offered.slice(0, 200)}`);

  // FIX 3 first, on a SECOND call later; this call tests the clock.
  console.log('[tap Return; the clock must continue, not restart]');
  await d.tapControl('returnToCall');
  await wait(9000);
  await d.screenshot(shot('UI4-after-return.png'));
  const back = await phoneText();
  const clock = (back.match(/\b(\d+):(\d\d)\b/) || [])[0];
  console.log('   phone clock after returning:', clock ?? '(none seen)');
  const seconds = clock ? Number(clock.split(':')[0]) * 60 + Number(clock.split(':')[1]) : -1;
  h.check('ui4', 'the returned clock continues the call (not 0:0x)', seconds > 35,
    `phone showed ${clock ?? 'nothing'} for a call already ~1 minute old`);

  console.log('[the laptop ends the call; the phone must not say reconnecting]');
  await ui.clickPanel(A.page, 'hangup').catch(() => {});
  await wait(12000);
  await d.screenshot(shot('UI4-after-remote-end.png'));
  const ended = await phoneText();
  h.check('ui4', 'the phone does not claim reconnecting after the other side ends',
    !/reconnect/i.test(ended), `phone text: ${ended.slice(0, 200)}`);

  console.log('[the chat list must preview the call, not the membership event]');
  await d.adb('shell', 'input', 'keyevent', 'KEYCODE_BACK').catch(() => {});
  await wait(4000);
  await d.screenshot(shot('UI4-chat-list.png'));
  const list = await phoneText();
  h.check('ui4', 'the chat list never shows the raw member event',
    !/famedly\.call\.member/i.test(list), `list text: ${list.slice(0, 240)}`);

  await A.browser.close();
  h.report();
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });

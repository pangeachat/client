// The four review fixes, browser to browser -- the same shared Dart the
// phone runs, so this is where they are proven first and cheapest.
//
//  1 a rejoined side's clock CONTINUES the call (both screens agree)
//  2 after the other side ends, nothing still claims "reconnecting"
//  3 the Return banner's red end ENDS the call for the other side
//  4 the chat list previews the call, not the membership plumbing
const h = require('./harness');
const { ui, mx, wait } = h;

const ROOM = process.env.CALL_ROOM || '!HgavfyvZrMpYhLFMLt';
const ROOM_ID = ROOM + ':pangea.localhost';

async function text(page) {
  try { return await page.evaluate(() => document.body.innerText || ''); }
  catch { return ''; }
}

/// The call clock as seconds, read off whichever surface shows it.
function clockSeconds(pageText) {
  const m = pageText.match(/\b(\d+):(\d{2})\b/);
  return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
}

async function clickByText(page, label) {
  return page.evaluate((want) => {
    const nodes = [...document.querySelectorAll('flt-semantics, [role=button], button, [aria-label]')];
    const hit = nodes.find((n) =>
      new RegExp(`(^|\\s)${want}(\\s|$)`, 'i').test(n.textContent || '') ||
      new RegExp(`(^|\\s)${want}(\\s|$)`, 'i').test(n.getAttribute?.('aria-label') || ''));
    if (hit) { hit.click(); return true; }
    return false;
  }, label);
}

async function connect(A, B, mA) {
  const rang = await h.actUntil('place',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickLabel(A.page, 'Call', { exact: true }).catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 });
  if (!rang) return false;
  await wait(3500);
  return h.actUntil('answer', async () => { await ui.clickBanner(B.page, 'answer'); },
    () => mx.hasMembership(B.token, ROOM_ID, B.userId), { tries: 5, gap: 3000 });
}

(async () => {
  const A = await h.openParticipant('learner', ROOM, 9811);
  const B = await h.openParticipant('calltester', ROOM, 9812);
  let mA = await h.mark(A.token, ROOM_ID);

  console.log('[1] a call, then B refreshes and returns');
  if (!(await connect(A, B, mA))) { console.log('FAIL: never connected'); h.report(); process.exit(2); }

  // PROVE the call is really up before refreshing anything. A run that
  // refreshes a call that never connected goes on to report the product
  // broken for a precondition it failed to meet itself.
  let live = false;
  for (let i = 0; i < 20 && !live; i++) {
    const [aIn, bIn, aText] = await Promise.all([
      mx.hasMembership(A.token, ROOM_ID, A.userId),
      mx.hasMembership(B.token, ROOM_ID, B.userId),
      text(A.page),
    ]);
    live = aIn && bIn && clockSeconds(aText) >= 0 && !/Ringing/i.test(aText);
    if (!live) await wait(2000);
  }
  h.check('rejoin', 'the call is genuinely up before the refresh', live,
    'never reached a two-sided, ticking call');
  if (!live) { h.report(); process.exit(2); }

  await wait(40000);                       // long enough that 0:0x is unmistakable
  await B.page.reload({ waitUntil: 'domcontentloaded' });

  // And wait for B to actually BE somewhere: a hard reload with the service
  // worker purged takes its time, and an empty page answers every question
  // with "no".
  let alive = false;
  for (let i = 0; i < 30 && !alive; i++) {
    alive = (await text(B.page)).trim().length > 0;
    if (!alive) await wait(2000);
  }
  h.check('rejoin', 'B came back up after the reload', alive, 'B stayed blank');

  // Diagnostics before judging: is the crumb there, is A still in the call,
  // and what does B's own log say about the scan?
  const crumb = await B.page.evaluate(
    () => window.localStorage.getItem('flutter.pangea.call.breadcrumb'));
  console.log('   B breadcrumb after reload:', crumb);
  console.log('   A still in the call:',
    await mx.hasMembership(A.token, ROOM_ID, A.userId));
  const bLog = [];
  B.page.on('console', (m) => {
    const t = m.text();
    if (/Rejoin offer|ReturnCard|withdraw|breadcrumb|call to return/i.test(t)) bLog.push(t.slice(0, 160));
  });

  let offered = false;
  for (let i = 0; i < 10 && !offered; i++) {
    offered = await ui.hasLabel(B.page, 'Return').catch(() => false) ||
      /Return/.test(await text(B.page));
    if (!offered) await wait(1500);
  }
  if (!offered) {
    console.log('   B page text:', (await text(B.page)).slice(0, 200).replace(/\n/g, ' | '));
    console.log('   B console:', bLog.slice(-8).join(' || ') || '(nothing)');
    console.log('   A in call now:', await mx.hasMembership(A.token, ROOM_ID, A.userId));
  }
  h.check('rejoin', 'B is offered the way back', offered, 'no Return banner');

  if (offered) {
    for (let i = 0; i < 5; i++) { if (await clickByText(B.page, 'Return')) break; await wait(1200); }
    await wait(9000);
    const secs = clockSeconds(await text(B.page));
    console.log(`   B's clock after returning: ${secs}s`);
    h.check('rejoin', "the returned clock continues the call, it does not restart", secs > 35,
      `showed ${secs}s for a call already about a minute old`);

    const aSecs = clockSeconds(await text(A.page));
    console.log(`   A's clock: ${aSecs}s`);
    h.check('rejoin', 'both sides read about the same clock',
      aSecs > 0 && secs > 0 && Math.abs(aSecs - secs) <= 15,
      `A=${aSecs}s B=${secs}s`);
  }

  console.log('[2] A ends the call; nothing may still say reconnecting');
  await ui.clickPanel(A.page, 'hangup').catch(() => {});
  await wait(12000);
  const bAfter = await text(B.page);
  h.check('rejoin', 'B never claims reconnecting after A ends', !/reconnect/i.test(bAfter),
    `B text: ${bAfter.slice(0, 180).replace(/\n/g, ' | ')}`);

  console.log('[3] a second call: B refuses the way back with the red end');
  await wait(6000);
  mA = await h.mark(A.token, ROOM_ID);
  if (await connect(A, B, mA)) {
    await wait(12000);
    await B.page.reload({ waitUntil: 'domcontentloaded' });
    await wait(14000);
    let back = false;
    for (let i = 0; i < 10 && !back; i++) {
      back = /Return/.test(await text(B.page));
      if (!back) await wait(1500);
    }
    if (back) {
      // The red control carries the hang-up label the panel uses.
      for (let i = 0; i < 5; i++) { if (await clickByText(B.page, 'Hang up')) break; await wait(1200); }
      const aEnded = await h.actUntil('A ends after B refuses', async () => {},
        async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)),
        { tries: 8, gap: 3000 });
      h.check('rejoin', "refusing the return ends the call for the OTHER side too", aEnded,
        'A was still holding the call long after B said no');
    } else {
      h.check('rejoin', 'the second call offered a way back', false, 'no banner to refuse');
    }
  }

  console.log('[4] the chat list previews the call, not the plumbing');
  await ui.clickPanel(A.page, 'hangup').catch(() => {});
  await wait(10000);
  await A.page.goto(`${h.APP}/?left=chats`, { waitUntil: 'domcontentloaded' });
  await wait(7000);
  const list = await text(A.page);
  h.check('rejoin', 'no raw call-member event in the chat list',
    !/famedly\.call\.member/i.test(list),
    `list text: ${list.slice(0, 220).replace(/\n/g, ' | ')}`);

  await A.browser.close(); await B.browser.close();
  h.report();
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });

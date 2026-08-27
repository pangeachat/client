// Walks a profile out of the onboarding wizard and proves the room opens.
const h = require('./harness');
const { ui, wait } = h;
// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM, shot } = h.cfg;
const who = process.argv[2] || 'learner';

const CHOICES = /^(learn|learner|student|english|spanish|beginner|a1|skip for now)$/i;
const NAV = /^(next|continue|done|finish|get started|let's go|save)$/i;

(async () => {
  try {
    const p = await h.openParticipant(who, ROOM, 9871);
    console.log(`${who}: already fine`);
    await p.browser.close();
    return;
  } catch (e) {
    console.log(`${who}: ${e.message}`);
  }
  const puppeteer = require('puppeteer-core');
  const browser = await puppeteer.connect({ browserURL: 'http://127.0.0.1:9871', defaultViewport: null });
  const pages = await browser.pages();
  const page = pages[pages.length - 1];
  await ui.enableSemantics(page).catch(() => {});
  await wait(1500);

  for (let step = 0; step < 25; step++) {
    if (await ui.hasLabel(page, 'Call').catch(() => false)) break;
    const labels = await ui.labels(page).catch(() => []);
    const leaves = await page.evaluate(() =>
      [...document.querySelectorAll('flt-semantics')]
        .filter((e) => !e.querySelector('flt-semantics'))
        .map((e) => (e.textContent || '').trim())
        .filter((t) => t && t.length < 40));
    console.log(`step ${step} ${page.url().replace(h.APP, '')} :: ${JSON.stringify(labels.slice(0, 3))} leaves=${JSON.stringify(leaves.slice(0, 8))}`);

    if (labels.some((l) => /alert/i.test(l))) {
      await page.keyboard.press('Escape');
      await wait(1500);
      continue;
    }
    // Real mouse clicks at the node's own position: a semantics node's
    // .click() does not always reach the Flutter hit-test, and a card that
    // looks clicked but was not made the walker loop on one page for ever.
    const rectOf = (text) => page.evaluate((want) => {
      const leaves = [...document.querySelectorAll('flt-semantics')]
        .filter((e) => !e.querySelector('flt-semantics'));
      const n = leaves.find((e) => (e.textContent || '').trim().toLowerCase() === want);
      if (!n) return null;
      const r = n.getBoundingClientRect();
      if (!r.width || !r.height) return null;
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    }, text);

    let did = null;
    for (const want of [
      'learn',
      'no',
      'english',
      'spanish',
      'beginner',
      'skip for now',
      'skip',
    ]) {
      const r = await rectOf(want);
      if (r) { await page.mouse.click(r.x, r.y); did = `choice:${want}`; break; }
    }
    if (did) { await wait(1500); await ui.enableSemantics(page).catch(() => {}); }
    for (const want of ['next', 'continue', 'done', 'finish', 'get started', 'save']) {
      const r = await rectOf(want);
      if (r) { await page.mouse.click(r.x, r.y); did = `${did ? did + ' + ' : ''}nav:${want}`; break; }
    }
    console.log(`   ${did || 'nothing to click'}`);
    if (!did) break;
    await wait(3500);
    await ui.enableSemantics(page).catch(() => {});
  }

  await page.goto(`${h.APP}/?left=chats,room:${ROOM}`, { waitUntil: 'domcontentloaded' });
  await wait(7000);
  await ui.enableSemantics(page);
  await wait(1500);
  const ok = await ui.hasLabel(page, 'Call').catch(() => false);
  console.log(`${who}: room opens = ${ok} (${page.url()})`);
  if (!ok) await page.screenshot({ path: shot(`stuck-${who}.png`) });
  await browser.close();
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });

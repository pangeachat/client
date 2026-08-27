// The grey box, hunted in the renderer where it actually happens.
//
// On the CanvasKit web renderer a Material carrying elevation or a clip
// repaints its whole region as an opaque grey rectangle the moment a child
// changes -- and a hover is a child changing. It has bitten the quick
// replies, the answer controls, and the return-to-call offer. Widget tests
// pin the CONVENTION (no elevated Material buttons, no Tooltip, no
// AnimatedSize); only a browser can prove the pixels, so this hovers every
// control and looks for a large flat grey block that was not there before.
const h = require('./harness');
const { ui, mx, wait } = h;

// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM, roomId: ROOM_ID, shot, shotsDir } = h.cfg;

/// The biggest run of near-identical mid-grey pixels in the banner's band.
///
/// Read off the page's own canvas rather than a screenshot file, so the
/// scenario needs no image library: any pixel whose channels are within a
/// few points of each other AND sit in the dull middle of the range is
/// "grey", and a genuine grey box is thousands of them in one rectangle.
/// [selfTest] paints a grey rectangle over the copied frame before counting,
/// which is the positive control: a counter that has never once fired is
/// indistinguishable from a counter that cannot fire, and this suite has been
/// bitten twice today by instruments that passed both ways.
async function greyBlock(page, band, { selfTest = false } = {}) {
  return page.evaluate(({ top, height, selfTest }) => {
    const canvas = document.querySelector('flt-glass-pane')?.shadowRoot
      ?.querySelector('canvas') ?? document.querySelector('canvas');
    if (!canvas) return { supported: false, grey: 0, total: 0 };
    const w = canvas.width, hgt = canvas.height;
    const off = document.createElement('canvas');
    off.width = w; off.height = hgt;
    const ctx = off.getContext('2d');
    ctx.drawImage(canvas, 0, 0);
    const scale = hgt / window.innerHeight;
    const y0 = Math.max(0, Math.floor(top * scale));
    const y1 = Math.min(hgt, Math.floor((top + height) * scale));
    if (y1 <= y0) return { supported: true, grey: 0, total: 0 };
    if (selfTest) {
      ctx.fillStyle = 'rgb(136,136,136)';
      ctx.fillRect(0, y0, w, y1 - y0);
    }
    const data = ctx.getImageData(0, y0, w, y1 - y0).data;
    let grey = 0;
    const total = data.length / 4;
    for (let i = 0; i < data.length; i += 4) {
      const r = data[i], g = data[i + 1], b = data[i + 2], a = data[i + 3];
      if (a < 200) continue;
      const flat = Math.abs(r - g) < 6 && Math.abs(g - b) < 6;
      const dull = r > 90 && r < 190;
      if (flat && dull) grey++;
    }
    return { supported: true, grey, total };
  }, { ...band, selfTest });
}

(async () => {
  const A = await h.openParticipant('learner', ROOM, 9781);
  const B = await h.openParticipant('calltester', ROOM, 9782);
  const mA = await h.mark(A.token, ROOM_ID);

  console.log('[ring the callee, then hover every control on the banner]');
  const rang = await h.actUntil('place',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickLabel(A.page, 'Call', { exact: true }).catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 3, gap: 4000 });
  h.check('grey', 'the call rang', rang, 'never rang');
  if (!rang) { h.report(); process.exit(2); }
  await wait(4000);

  // The banner occupies the top strip; measure that band only, so the rest
  // of the app's own greys cannot drown the signal.
  const band = { top: 90, height: 130 };
  // Prove the instrument first: a synthetic grey band MUST light it up.
  const control = await greyBlock(B.page, band, { selfTest: true });
  h.check('grey', 'the grey detector can actually detect grey',
    control.supported && control.grey > control.total * 0.8,
    `a fully grey band counted only ${control.grey}/${control.total}`);

  const base = await greyBlock(B.page, band);
  if (!base.supported) {
    console.log('   (no canvas to read; skipping the pixel check)');
  }
  console.log(`   baseline grey pixels in the banner band: ${base.grey}/${base.total}`);

  const points = [
    ['decline', ui.BANNER.decline],
    ['answer', ui.BANNER.answer],
    ['message', ui.BANNER.message],
    ['card body', { x: 500, y: 126 }],
  ];
  let worst = base.grey;
  let worstAt = 'baseline';
  for (const [name, p] of points) {
    await B.page.mouse.move(p.x, p.y);
    await wait(700);
    const after = await greyBlock(B.page, band);
    console.log(`   hover ${name}: ${after.grey}`);
    if (after.grey > worst) { worst = after.grey; worstAt = name; }
  }

  // A real grey box covers the card. Anything under a modest multiple of the
  // baseline is ordinary dark-theme chrome, not the failure.
  const blewUp = base.supported && worst > Math.max(base.grey * 3, 20000);
  h.check('grey', 'hovering the ring banner paints no grey box', !blewUp,
    `worst was ${worst} grey pixels while hovering ${worstAt} (baseline ${base.grey})`);

  if (blewUp) {
    await B.page.screenshot({ path: shot('GREY-hover.png') });
    console.log(`   screenshot: ${shotsDir}/GREY-hover.png`);
  }

  await ui.clickPanel(A.page, 'hangup').catch(() => {});
  await wait(4000);
  await A.browser.close(); await B.browser.close();
  h.report();
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });

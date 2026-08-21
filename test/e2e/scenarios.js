// Scenario suite. Each one drives both clients, then asserts what BOTH
// participants' timelines contain -- the check no unit test and no code review
// can make, and the one that would have caught the ghost-card bug.
const h = require('./harness');
const { ui, mx, wait } = h;

const ROOM_LOCALPART = '!HgavfyvZrMpYhLFMLt';
const ROOM_ID = ROOM_LOCALPART + ':pangea.localhost';

/// Both sides must end up with the SAME events. Any asymmetry is a bug: a room
/// is shared, so a row one person has and the other does not is by definition
/// wrong.
async function assertSymmetric(scenario, A, B, markA, markB) {
  const evA = await h.since(A.token, ROOM_ID, markA);
  const evB = await h.since(B.token, ROOM_ID, markB);
  const c = h.compare(evA, A.userId, evB, B.userId);
  h.check(scenario, 'both sides received the same events', c.onlyA.length === 0 && c.onlyB.length === 0,
    `only ${A.name}: ${JSON.stringify(c.onlyA)}  only ${B.name}: ${JSON.stringify(c.onlyB)}`);
  h.check(scenario, 'both sides have the same number of call cards', c.aCards.length === c.bCards.length,
    `${A.name}=${c.aCards.length} ${B.name}=${c.bCards.length}`);
  // Every card must read as the mirror image on the two sides.
  c.aCards.forEach((ca, i) => {
    const cb = c.bCards[i];
    if (!cb) return;
    const mirrored = ca.outgoing !== cb.outgoing || (!ca.outgoing && !cb.outgoing);
    h.check(scenario, `card ${i} reads correctly on both sides`, ca.caller === cb.caller && mirrored,
      `${A.name}="${ca.label}" ${B.name}="${cb.label}" caller=${ca.caller}/${cb.caller}`);
  });
  return c;
}

/// The precondition for every scenario that places a call: the ring must have
/// actually reached the room. Asserting it separately is what tells a broken
/// decline apart from a call that never rang in the first place.
/// Places a call and PROVES it rang, retrying the click.
///
/// A single click plus a fixed sleep is a race: it can land while the app is
/// rebuilding after the previous call's teardown and simply do nothing, with no
/// error anywhere. Retrying against the ring event makes the scenario
/// deterministic and keeps a genuine failure to ring a real failure.
async function placeCall(scenario, caller, markId, roomLocalpart) {
  const rang = await h.actUntil(
    'place call',
    async () => {
      await h.ensureRoom(caller, roomLocalpart);
      await ui.clickLabel(caller.page, 'Call', { exact: true }).catch(() => {});
    },
    async () => (await h.since(caller.token, ROOM_ID, markId)).some(
      (e) => e.type === mx.RING && e.sender === caller.userId,
    ),
    { tries: 4, gap: 4000 },
  );
  if (!rang) {
    const f = `/tmp/callweb/FAIL-place-${scenario.replace(/[^a-z]+/gi, '-')}.png`;
    await caller.page.screenshot({ path: f }).catch(() => {});
    console.log(`   (screenshot: ${f}; labels: ${JSON.stringify(await ui.labels(caller.page))})`);
  }
  h.check(scenario, 'placing a call rang the other side', rang, 'no ring event ever reached the room');
  return rang;
}

async function assertRang(scenario, caller, markId) {
  const evs = await h.since(caller.token, ROOM_ID, markId);
  const rs = evs.filter((e) => e.type === mx.RING && e.sender === caller.userId);
  if (rs.length !== 1) {
    // Evidence, not guesswork: a failing scenario leaves a screenshot behind.
    const f = `/tmp/callweb/FAIL-${scenario.replace(/[^a-z]+/gi, '-')}-${caller.name}.png`;
    await caller.page.screenshot({ path: f }).catch(() => {});
    console.log(`   (screenshot: ${f}; labels: ${JSON.stringify(await ui.labels(caller.page))})`);
  }
  const rings = evs.filter((e) => e.type === mx.RING && e.sender === caller.userId);
  h.check(scenario, 'the ring reached the room', rings.length === 1,
    `${rings.length} rings. Caller's events since mark: ${JSON.stringify(evs.filter((e) => e.sender === caller.userId).map((e) => e.type))}`);
  return rings.length === 1;
}

function noPageErrors(scenario, p) {
  h.check(scenario, `${p.name} had no unhandled errors`, p.errors.length === 0, JSON.stringify(p.errors.slice(0, 3)));
}

async function run() {
  console.log('opening two clients...');
  const A = await h.openParticipant('learner', ROOM_LOCALPART, 9541);
  const B = await h.openParticipant('calltester', ROOM_LOCALPART, 9542);
  console.log(`  ${A.name} ${A.userId}\n  ${B.name} ${B.userId}`);

  try {
    // ---------------------------------------------------------------- 1
    {
      const s = 'answer then caller hangs up';
      console.log(`\n[${s}]`);
      await h.ensureRoom(A, ROOM_LOCALPART); await h.ensureRoom(B, ROOM_LOCALPART);
      const mA = await h.mark(A.token, ROOM_ID), mB = await h.mark(B.token, ROOM_ID);
      await ui.clickLabel(A.page, 'Call', { exact: true });
      await wait(5000);
      // The banner is not in the accessibility tree, so it is clicked by
      // position -- and the click is PROVEN by the membership it must produce.
      const joined = await h.actUntil(
        'answer',
        () => ui.clickBanner(B.page, 'answer'),
        () => mx.hasMembership(B.token, ROOM_ID, B.userId),
      );
      h.check(s, 'answering actually joined the call', joined, 'the callee never published a call membership');
      await wait(6000);
      {
        const left = await h.actUntil(
          'hangup',
          () => ui.clickPanel(A.page, 'hangup'),
          async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)),
        );
        h.check(s, 'hanging up actually left the call', left, 'the caller still holds a live membership');
        await wait(6000);
      }
      const c = await assertSymmetric(s, A, B, mA, mB);
      const answered = c.aCards.filter((x) => x.answered);
      h.check(s, 'exactly one answered card', answered.length === 1, `got ${answered.length}: ${JSON.stringify(c.aCards.map((x) => x.label))}`);
      if (answered[0]) h.check(s, 'the caller is recorded as the caller', answered[0].caller === A.userId, answered[0].caller);
    }

    // ---------------------------------------------------------------- 2
    {
      const s = 'callee declines';
      console.log(`\n[${s}]`);
      await h.ensureRoom(A, ROOM_LOCALPART); await h.ensureRoom(B, ROOM_LOCALPART);
      const mA = await h.mark(A.token, ROOM_ID), mB = await h.mark(B.token, ROOM_ID);
      await placeCall(s, A, mA, ROOM_LOCALPART);
      const declined = await h.actUntil(
        'decline',
        () => ui.clickBanner(B.page, 'decline'),
        async () => (await h.since(B.token, ROOM_ID, mB)).some(
          (e) => e.type === mx.DECLINE && e.sender === B.userId,
        ),
      );
      h.check(s, 'declining actually sent a decline', declined, 'the callee never sent a decline event');
      // The caller needs to notice the decline, tear down and write the card.
      await wait(12000);
      const c = await assertSymmetric(s, A, B, mA, mB);
      const dec = c.aCards.filter((x) => x.declined);
      h.check(s, 'exactly one declined card', dec.length === 1, `got ${dec.length}: ${JSON.stringify(c.aCards.map((x) => x.label))}`);
      if (dec[0]) {
        h.check(s, 'caller sees "Call declined"', dec[0].label === 'Call declined', dec[0].label);
        const mine = c.bCards.find((x) => x.id === dec[0].id);
        if (mine) h.check(s, 'callee sees "You declined this call"', mine.label === 'You declined this call', mine.label);
      }
    }

    // ---------------------------------------------------------------- 3
    {
      const s = 'redial immediately after hanging up';
      console.log(`\n[${s}]`);
      await h.ensureRoom(A, ROOM_LOCALPART); await h.ensureRoom(B, ROOM_LOCALPART);
      const mA = await h.mark(A.token, ROOM_ID), mB = await h.mark(B.token, ROOM_ID);
      await ui.clickLabel(A.page, 'Call', { exact: true });
      await wait(4000);
      await ui.clickPanel(A.page, 'hangup');
      await wait(2500);
      // Straight back in. This is what used to say "you are in a call".
      let redialled = true;
      try { await ui.clickLabel(A.page, 'Call', { exact: true, timeout: 8000 }); }
      catch (e) { redialled = false; }
      h.check(s, 'the call button is usable again right after hanging up', redialled, 'Call was not clickable');
      await wait(6000);
      const busy = await ui.hasLabel(A.page, 'already in a call');
      h.check(s, 'no "already in a call" error', !busy, 'the redial was refused');
      await ui.clickPanel(A.page, 'hangup');
      await wait(9000);
      await assertSymmetric(s, A, B, mA, mB);
    }

    // ---------------------------------------------------------------- 4
    {
      const s = 'nobody answers';
      console.log(`\n[${s}]`);
      await h.ensureRoom(A, ROOM_LOCALPART); await h.ensureRoom(B, ROOM_LOCALPART);
      const mA = await h.mark(A.token, ROOM_ID), mB = await h.mark(B.token, ROOM_ID);
      await placeCall(s, A, mA, ROOM_LOCALPART);
      // Ring lifetime is 30s. Wait it out WITHOUT navigating either client --
      // reopening a room mid-call reloads the page and cancels the very call
      // being measured, which is why this scenario reported no card at all.
      await wait(46000);
      const c = await assertSymmetric(s, A, B, mA, mB);
      const missed = c.aCards.filter((x) => !x.answered && !x.declined);
      h.check(s, 'exactly one missed card', missed.length === 1, `got ${missed.length}: ${JSON.stringify(c.aCards.map((x) => x.label))}`);
      if (missed[0]) {
        h.check(s, 'caller sees "No answer"', missed[0].label === 'No answer', missed[0].label);
        const theirs = c.bCards.find((x) => x.id === missed[0].id);
        if (theirs) h.check(s, 'callee sees "Missed call"', theirs.label === 'Missed call', theirs.label);
      }
      await ui.clickPanel(A.page, 'hangup');
      await wait(3000);
    }

    noPageErrors('overall', A);
    noPageErrors('overall', B);
  } finally {
    await A.browser.close().catch(() => {});
    await B.browser.close().catch(() => {});
  }
  process.exit(h.report() === 0 ? 0 : 1);
}

run().catch((e) => { console.error('HARNESS ERROR:', e.message); h.report(); process.exit(2); });

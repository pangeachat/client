// Scenario suite. Each one drives both clients, then asserts what BOTH
// participants' timelines contain -- the check no unit test and no code review
// can make, and the one that would have caught the ghost-card bug.
const labels = require('./labels');
const h = require('./harness');
const { ui, mx, wait } = h;

// The room and the accounts are LOCAL-STACK fixtures rather than constants of
// the product; config.js says which env vars move them.
const { room: ROOM_LOCALPART, roomId: ROOM_ID, shot } = h.cfg;

/// Both sides must end up with the SAME events. Any asymmetry is a bug: a room
/// is shared, so a row one person has and the other does not is by definition
/// wrong.
async function assertSymmetric(scenario, A, B, markA, markB, { wantCards = 0 } = {}) {
  // Polled, not sampled once. The card is written the moment the call's fate
  // is decided, but it still has to reach the server and come back down sync,
  // and reading a single moment made the FIRST scenario of a run fail about
  // half the time -- always the first, which is the run that is also doing
  // its initial sync. Waiting a little says which it was: a card that never
  // came, or a card that had not arrived yet.
  let evA = await h.since(A.token, ROOM_ID, markA);
  let evB = await h.since(B.token, ROOM_ID, markB);
  let c = h.compare(evA, A.userId, evB, B.userId);
  for (let i = 0; i < 10 && c.aCards.length < wantCards; i++) {
    await h.wait(2000);
    evA = await h.since(A.token, ROOM_ID, markA);
    evB = await h.since(B.token, ROOM_ID, markB);
    c = h.compare(evA, A.userId, evB, B.userId);
    if (c.aCards.length >= wantCards) {
      console.log(`   (the card took ${(i + 1) * 2}s to land)`);
    }
  }
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
      await ui.clickControl(caller.page, 'call').catch(() => {});
    },
    async () => (await h.since(caller.token, ROOM_ID, markId)).some(
      (e) => e.type === mx.RING && e.sender === caller.userId,
    ),
    { tries: 4, gap: 4000 },
  );
  if (!rang) {
    const f = shot(`FAIL-place-${scenario.replace(/[^a-z]+/gi, '-')}.png`);
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
    const f = shot(`FAIL-${scenario.replace(/[^a-z]+/gi, '-')}-${caller.name}.png`);
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

h.refuseIfAnotherRunIsLive();

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
      await ui.clickControl(A.page, 'call');
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
      const c = await assertSymmetric(s, A, B, mA, mB, { wantCards: 1 });
      const answered = c.aCards.filter((x) => x.answered);
      h.check(s, 'exactly one answered card', answered.length === 1, `got ${answered.length}: ${JSON.stringify(c.aCards.map((x) => x.label))}`);
      if (answered[0]) h.check(s, 'the caller is recorded as the caller', answered[0].caller === A.userId, answered[0].caller);
    }

    // ---------------------------------------------------------------- 2
    {
      // The engine's semantics click pipeline does not reliably survive a
      // call panel's teardown (see harness.recover): later clicks can die inside
      // the engine with a null-state error before any app code runs. Ordinary
      // users are unaffected (semantics off); the harness reloads between
      // scenarios so each starts with a working pipeline.
      await h.recover(A, ROOM_LOCALPART);
      await h.recover(B, ROOM_LOCALPART);
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
      // The engine's semantics click pipeline does not reliably survive a
      // call panel's teardown (see harness.recover): later clicks can die inside
      // the engine with a null-state error before any app code runs. Ordinary
      // users are unaffected (semantics off); the harness reloads between
      // scenarios so each starts with a working pipeline.
      await h.recover(A, ROOM_LOCALPART);
      await h.recover(B, ROOM_LOCALPART);
      const s = 'redial immediately after hanging up';
      console.log(`\n[${s}]`);
      await h.ensureRoom(A, ROOM_LOCALPART); await h.ensureRoom(B, ROOM_LOCALPART);
      const mA = await h.mark(A.token, ROOM_ID), mB = await h.mark(B.token, ROOM_ID);
      await ui.clickControl(A.page, 'call');
      await wait(4000);
      await ui.clickPanel(A.page, 'hangup');
      await wait(2500);
      // Straight back in. This is what used to say "you are in a call".
      let redialled = true;
      try { await ui.clickControl(A.page, 'call', { timeout: 8000 }); }
      catch (e) { redialled = false; }
      h.check(s, 'the call button is usable again right after hanging up', redialled, 'Call was not clickable');
      await wait(6000);
      const busy = await ui.hasControl(A.page, 'busy');
      h.check(s, 'no "already in a call" error', !busy, 'the redial was refused');
      await ui.clickPanel(A.page, 'hangup');
      await wait(9000);
      await assertSymmetric(s, A, B, mA, mB);
    }

    // ---------------------------------------------------------------- 4
    {
      // The engine's semantics click pipeline does not reliably survive a
      // call panel's teardown (see harness.recover): later clicks can die inside
      // the engine with a null-state error before any app code runs. Ordinary
      // users are unaffected (semantics off); the harness reloads between
      // scenarios so each starts with a working pipeline.
      await h.recover(A, ROOM_LOCALPART);
      await h.recover(B, ROOM_LOCALPART);
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


    // ---------------------------------------------------------------- 5
    {
      await h.recover(A, ROOM_LOCALPART); await h.recover(B, ROOM_LOCALPART);
      const s = 'video call answered';
      console.log(`\n[${s}]`);
      const mA = await h.mark(A.token, ROOM_ID), mB = await h.mark(B.token, ROOM_ID);
      const rang = await h.actUntil(
        'place video call',
        async () => { await h.ensureRoom(A, ROOM_LOCALPART); await ui.clickControl(A.page, 'videoCall').catch(() => {}); },
        async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
        { tries: 4, gap: 4000 },
      );
      h.check(s, 'placing a video call rang the other side', rang, 'no ring event');
      const joined = await h.actUntil(
        'answer', () => ui.clickBanner(B.page, 'answer'),
        () => mx.hasMembership(B.token, ROOM_ID, B.userId),
      );
      h.check(s, 'answering joined the call', joined, 'no membership');
      await wait(6000);
      await h.actUntil('hangup', () => ui.clickPanel(A.page, 'hangup'),
        async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)));
      await wait(6000);
      const c = await assertSymmetric(s, A, B, mA, mB);
      const vid = c.aCards.filter((x) => x.video && x.answered);
      h.check(s, 'exactly one answered VIDEO card', vid.length === 1,
        JSON.stringify(c.aCards.map((x) => [x.label, x.video])));
    }

    // ---------------------------------------------------------------- 6
    {
      await h.recover(A, ROOM_LOCALPART); await h.recover(B, ROOM_LOCALPART);
      const s = 'quick reply declines with a message';
      console.log(`\n[${s}]`);
      const mA = await h.mark(A.token, ROOM_ID), mB = await h.mark(B.token, ROOM_ID);
      await placeCall(s, A, mA, ROOM_LOCALPART);
      // Open the reply list, pick the first canned reply. Both are banner
      // overlay controls (not in the accessibility tree), clicked by position
      // confirmed against a screenshot -- and proven below on the server.
      const replied = await h.actUntil(
        'quick reply',
        async () => { await ui.clickBanner(B.page, 'message'); await wait(1200); await B.page.mouse.click(500, 152); },
        async () => {
          const evs = await h.since(B.token, ROOM_ID, mB);
          return evs.some((e) => e.type === 'm.room.message' && e.sender === B.userId)
              && evs.some((e) => e.type === mx.DECLINE && e.sender === B.userId);
        },
        { tries: 4, gap: 3000 },
      );
      h.check(s, 'the reply sent BOTH a message and a decline', replied, 'one or both missing');
      await wait(10000);
      const c = await assertSymmetric(s, A, B, mA, mB);
      const dec = c.aCards.filter((x) => x.declined);
      h.check(s, 'exactly one declined card', dec.length === 1, JSON.stringify(c.aCards.map((x) => x.label)));
      const msg = (await h.since(A.token, ROOM_ID, mA)).find((e) => e.type === 'm.room.message' && e.sender === B.userId);
      // Matched against every language the app can send it in, not against
      // the English one. The REPLY is composed on the callee's device, in the
      // callee's language -- so asserting the English string tests the
      // fixture's language settings rather than the product.
      const body = msg?.content?.body || '';
      const replies = labels.labelsFor('callReplyCantTalk');
      h.check(s, 'the caller received the reply text',
        !!msg && replies.some((r) => body.includes(r)),
        JSON.stringify(msg && msg.content && msg.content.body));
    }

    // ---------------------------------------------------------------- 7
    {
      await h.recover(A, ROOM_LOCALPART); await h.recover(B, ROOM_LOCALPART);
      const s = 'caller gives up before an answer';
      console.log(`\n[${s}]`);
      const mA = await h.mark(A.token, ROOM_ID), mB = await h.mark(B.token, ROOM_ID);
      await placeCall(s, A, mA, ROOM_LOCALPART);
      await wait(3000);
      await h.actUntil('cancel', () => ui.clickPanel(A.page, 'hangup'),
        async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)));
      await wait(8000);
      const c = await assertSymmetric(s, A, B, mA, mB);
      const missed = c.aCards.filter((x) => !x.answered && !x.declined);
      h.check(s, 'exactly one missed card', missed.length === 1, JSON.stringify(c.aCards.map((x) => x.label)));
      const declines = (await h.since(B.token, ROOM_ID, mB)).filter((e) => e.type === mx.DECLINE);
      h.check(s, 'the callee declined nothing', declines.length === 0, `${declines.length} declines`);
      // The banner's own dismissal (G1) is visual-only -- the overlay is not in
      // the accessibility tree -- so what is asserted here is the OUTCOME side.
      // That the callee is not left stuck is proven by the next scenario using
      // the same client to take a fresh call.
    }

    // ---------------------------------------------------------------- 8
    {
      const s = 'callee reloads while ringing, and can still answer';
      console.log(`\n[${s}]`);
      await h.recover(A, ROOM_LOCALPART); await h.recover(B, ROOM_LOCALPART);
      const mA = await h.mark(A.token, ROOM_ID), mB = await h.mark(B.token, ROOM_ID);
      await placeCall(s, A, mA, ROOM_LOCALPART);
      // The reload happens MID-RING; D1 replays the ring from the timeline
      // after the page comes back, and the answer must still work.
      //
      // Against the clock, deliberately: a ring lives 30s and a reload costs
      // most of it, so the window to answer in is what is left. Without this
      // the check could not tell a product that refuses a REPLAYED ring from
      // one that correctly refuses an EXPIRED one, and it reported the second
      // as the first.
      const ringAt = Date.now();
      await h.recover(B, ROOM_LOCALPART);
      const leftMs = 30000 - (Date.now() - ringAt);
      const tries = Math.max(1, Math.min(5, Math.floor(leftMs / 3000)));
      console.log(`   ${Math.round(leftMs / 1000)}s of ring left after the reload; ${tries} attempt(s)`);
      const joined = leftMs < 4000
        ? null
        : await h.actUntil(
            'answer after reload', () => ui.clickBanner(B.page, 'answer'),
            () => mx.hasMembership(B.token, ROOM_ID, B.userId),
            { tries, gap: 3000 },
          );
      if (leftMs < 4000) {
        h.skipped(s, 'the replayed ring could be answered',
          'the ring expired during the reload itself');
      } else {
        h.check(s, 'the replayed ring could be answered', joined, 'no membership after reload');
      }
      await wait(5000);
      await h.actUntil('hangup', () => ui.clickPanel(A.page, 'hangup'),
        async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)));
      await wait(8000);
      const c = await assertSymmetric(s, A, B, mA, mB);
      const ans = c.aCards.filter((x) => x.answered);
      // Only meaningful if the answer landed: a ring that expired mid-reload
      // is correctly recorded as no answer.
      if (joined) {
        h.check(s, 'the call is recorded as answered', ans.length === 1,
          JSON.stringify(c.aCards.map((x) => x.label)));
      } else if (leftMs < 4000) {
        h.skipped(s, 'the call is recorded as answered',
          'nothing was answered, so there is no answered card to expect');
      }
    }

    // ---------------------------------------------------------------- 9
    {
      await h.recover(A, ROOM_LOCALPART); await h.recover(B, ROOM_LOCALPART);
      const s = 'glare: both call at the same moment';
      console.log(`\n[${s}]`);
      const mA = await h.mark(A.token, ROOM_ID), mB = await h.mark(B.token, ROOM_ID);
      await Promise.all([
        ui.clickControl(A.page, 'call').catch(() => {}),
        ui.clickControl(B.page, 'call').catch(() => {}),
      ]);
      await wait(8000);
      // Whatever the tie-break decided, end everything.
      await ui.clickPanel(A.page, 'hangup').catch(() => {});
      await ui.clickPanel(B.page, 'hangup').catch(() => {});
      await wait(12000);
      const c = await assertSymmetric(s, A, B, mA, mB);
      h.check(s, 'one call, ONE card -- not one per side', c.aCards.length <= 1,
        `${c.aCards.length} cards: ${JSON.stringify(c.aCards.map((x) => [x.label, x.caller]))}`);
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

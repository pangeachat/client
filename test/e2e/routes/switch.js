// The device-switch routes (#3350 route 5; client#9173, client#8878,
// choreo#3354): the peer calls the learner, the learner answers on device one,
// MOVE_AT seconds after the ring opens the call on device two and presses
// "Use this device", talks on, and hangs up there.
//
// Pass criteria asked of the server: both of the learner's stretches are
// transcribed (device one's words AND device two's), both recordings exist and
// are linked (handed_over_to / continued_from), ONE complete full-call
// recording names every recording, the switched device's clock agrees with the
// peer's, and the usual #3350 criteria (punctuation, playback, credit once).
const R = require('./lib');

const { h, ui, mx, wait } = R;

async function runSwitch({ id, moveAtS, talkAfterS = 40, sub = { L: true, P: true } }) {
  const s = id;
  const opened = [];
  const roomLp = R.rooms().learner_calltester;
  const roomId = R.fullRoomId(roomLp);
  try {
    console.log(`[${s}] voice, both subscribed, switch device at ~${moveAtS}s`);
    R.refuseIfNotLocal();
    h.refuseIfAnotherRunIsLive();
    await R.refuseIfLearning('learner', 'en');
    await R.refuseIfLearning('calltester', 'en');
    await R.ensureSubscriptions({ learner: sub.L, calltester: sub.P });
    await R.waitNoLiveCall(['learnerFirstDevice', 'calltester'], roomId);

    const L1 = await R.openP('learnerFirstDevice', roomLp, 9761, { wav: R.fixture('learner') });
    opened.push(L1);
    const L2 = await R.openP('learnerSecondDevice', roomLp, 9762, { wav: R.fixture('learner2') });
    opened.push(L2);
    const P = await R.openP('calltester', roomLp, 9763, { wav: R.fixture('peer') });
    opened.push(P);
    const LEARNER = L1.userId;

    const call = await R.placeAndAnswer(s, P, null, roomId, { answer: false });
    if (!call) return R.finish(s, opened, {});
    let d1 = null;
    for (let i = 0; i < 15 && !d1; i++) {
      await ui.clickBanner(L1.page, 'answer').catch(() => {});
      await wait(2000);
      const devs = await mx.liveMembershipDevices(L1.token, roomId, LEARNER);
      if (devs.length === 1) d1 = devs[0];
    }
    h.check(s, 'device one answered', !!d1, 'no learner membership');
    if (!d1) return R.finish(s, opened, {});
    const answeredAt = Date.now();

    const waitMs = call.ringAt + moveAtS * 1000 - Date.now();
    if (waitMs > 0) await wait(waitMs);
    const preClock = { learner: await R.clockOf(L1), peer: await R.clockOf(P) };

    console.log('   (device two joins the call under way)');
    let d2 = null;
    for (let i = 0; i < 8 && !d2; i++) {
      await h.ensureRoom(L2, roomLp);
      await ui.clickControl(L2.page, 'call').catch(() => {});
      for (let j = 0; j < 6 && !d2; j++) {
        await wait(2000);
        const devs = await mx.liveMembershipDevices(L1.token, roomId, LEARNER);
        d2 = devs.find((d) => d !== d1) || null;
      }
    }
    h.check(s, 'device two joined the call', !!d2, 'no second learner membership');
    if (!d2) return R.finish(s, opened, {});

    const useThis = new Set(R.L('callDevicesUseThis'));
    let clicked = false;
    let promptOnOne = false;
    for (let i = 0; i < 20 && !clicked; i++) {
      const on2 = await ui.labels(L2.page).catch(() => []);
      const on1 = await ui.labels(L1.page).catch(() => []);
      promptOnOne = promptOnOne || R.anyLabel(on1, 'callDevicesTitle');
      const label = on2.find((n) => useThis.has(n));
      if (label) {
        const r = await ui.findRect(L2.page, label, { exact: true }).catch(() => null);
        if (r) { await L2.page.mouse.click(r.x, r.y); clicked = true; }
      }
      if (!clicked) await wait(2000);
    }
    await R.dumpLabels(L2, 'after-use-this');
    h.check(s, 'device two was offered "Use this device" and it was pressed', clicked, 'no prompt on device two');
    await wait(8000);
    const on1 = await R.dumpLabels(L1, 'after-move');
    h.check(s, 'device one says the call continues on the other device', R.anyLabel(on1, 'callContinuingElsewhere'),
      'no "This call is continuing on your other device." on device one');
    const peerStill = await mx.liveMembershipDevices(P.token, roomId, P.userId);
    h.check(s, 'the call carried on after the move (the peer is still in it)', peerStill.length === 1, `${peerStill.length}`);

    // Timer sync (#9173): sampled on both screens at the same moment, twice.
    const clocks = [];
    for (let i = 0; i < 2; i++) {
      await wait(10000);
      const [c2, cp] = await Promise.all([R.clockOf(L2), R.clockOf(P)]);
      clocks.push({ device2: c2, peer: cp, sinceAnswerS: Math.round((Date.now() - answeredAt) / 1000) });
    }
    R.save('clocks.json', { preClock, clocks });
    const readable = clocks.filter((c) => c.device2 != null && c.peer != null);
    if (readable.length < clocks.length) h.skipped(s, "the switched device's clock agrees with the peer's (#9173)", `the call clock is not in the semantics tree: ${JSON.stringify(clocks)}`);
    else h.check(s, "the switched device's clock agrees with the peer's (#9173)", readable.every((c) => Math.abs(c.device2 - c.peer) <= 3),
      JSON.stringify(readable));

    await wait(Math.max(0, talkAfterS - 20) * 1000);
    const callSeconds = Math.round((Date.now() - answeredAt) / 1000);
    await h.actUntil('hang up', () => ui.clickPanel(L2.page, 'hangup').catch(() => {}),
      async () => (await mx.liveMembershipDevices(L1.token, roomId, LEARNER)).length === 0, { tries: 5, gap: 3000 });

    await R.watchLoading(s, P, { doneAlready: async () => (await R.related(P.token, roomId, call.callKey, R.MERGED)).length >= 1 });
    const got = await R.collect(P.token, roomId, call.callKey, { halves: 3, audio: 3, merged: 1, settleS: 300 });
    R.save('events.json', { callKey: call.callKey, d1, d2, callSeconds,
      transcripts: got.transcripts.map(R.summarise), audio: got.audio.map(R.summarise), merged: got.merged.map(R.summarise), clock: got.clock.map(R.summarise) });

    const mineAudio = got.audio.filter((e) => e.sender === LEARNER);
    const a1 = mineAudio.find((e) => e.content?.device_id === d1);
    const a2 = mineAudio.find((e) => e.content?.device_id === d2);
    h.check(s, 'device one (moved FROM) saved its recording', !!a1, `learner recordings from: ${mineAudio.map((e) => e.content?.device_id).join(', ') || 'none'}`);
    h.check(s, 'device two (moved TO) saved its recording', !!a2, `learner recordings from: ${mineAudio.map((e) => e.content?.device_id).join(', ') || 'none'}`);
    h.check(s, 'the peer saved a recording', got.audio.some((e) => e.sender === P.userId), 'no call_audio from the peer');
    h.check(s, 'device one links to device two (handed_over_to)', a1?.content?.handed_over_to === d2, `handed_over_to=${a1?.content?.handed_over_to}`);
    h.check(s, 'device two links back to device one (continued_from)', a2?.content?.continued_from === d1, `continued_from=${a2?.content?.continued_from}`);

    const learnerText = got.transcripts.filter((e) => (e.content?.spoken_by || e.sender) === LEARNER).map(R.spoken).join(' ');
    const pre = R.hitsOf(learnerText, R.WORDS.learner);
    const post = R.hitsOf(learnerText, R.WORDS.learner2);
    h.check(s, "the learner's stretch BEFORE the switch is transcribed", pre.length >= 2, `${pre.length} of device one's words`);
    h.check(s, "the learner's stretch AFTER the switch is transcribed (#9173)", post.length >= 2, `${post.length} of device two's words`);
    const peerText = got.transcripts.filter((e) => (e.content?.spoken_by || e.sender) === P.userId).map(R.spoken).join(' ');
    h.check(s, "the peer's turns are transcribed", R.hitsOf(peerText, R.WORDS.peer).length >= 2, 'fewer than two peer words');
    const crossL = R.hitsOf(learnerText, R.WORDS.peer);
    const crossP = R.hitsOf(peerText, [...R.WORDS.learner, ...R.WORDS.learner2]);
    h.check(s, "neither person's half carries the other's words", crossL.length < 2 && crossP.length < 2,
      `learner half has peer words ${crossL.join(',')}; peer half has learner words ${crossP.join(',')}`);
    const withWords = got.transcripts.filter((e) => R.spoken(e).trim());
    h.check(s, 'the transcript shows punctuation', withWords.length > 0 && withWords.every((e) => /[.?!,;]/.test(R.spoken(e))),
      `${withWords.filter((e) => !/[.?!,;]/.test(R.spoken(e))).length}/${withWords.length} halves without punctuation`);

    const ids = new Set(got.audio.map((e) => e.event_id));
    const whole = got.merged.filter((m) => {
      const src = new Set(m.content?.source_event_ids || []);
      return m.content?.complete === true && src.size === ids.size && [...ids].every((i) => src.has(i));
    });
    h.check(s, 'ONE complete full-call recording names every recording (#8878, #3354)', whole.length === 1,
      `${got.merged.length} merged, ${whole.length} complete over all ${ids.size}`);
    await R.assertPlays(s, P.token, whole[0], callSeconds);

    const scP = { name: P.name, ...(await R.readTranscriptScreen(P)) };
    const scL = { name: L2.name, ...(await R.readTranscriptScreen(L2)) };
    R.assertScreens(s, [scP, scL], { subscribed: [scP, scL], unsubscribed: [], anySubscribed: true, callSeconds });

    await R.checkCreditOnce(s, [L2, P], [call.ring?.event_id, call.callKey,
      ...(await R.eventsSince(P.token, roomId, call.mark, [mx.CALL])).map((e) => e.event_id)].filter(Boolean), call.ringAt - 60000);
    await R.confirmSubscriptions(s, { learner: sub.L, calltester: sub.P });
  return R.finish(s, opened, { moveAtS, callKey: call.callKey, d1, d2 });
  } catch (e) {
    return R.fatal(s, opened)(e);
  }
}

module.exports = { runSwitch };

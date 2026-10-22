// Route 9 (pangeachat/2-step-choreographer#3350): video, both subscribed, the
// SAME call opened on the learner's second device (client#9168): both devices
// are told "This call is open on two of your devices", the second device
// presses "Leave the call here", and the first carries on. The device that did
// not carry on writes no half and no recording; the call's transcript and
// full recording are complete.
const R = require('./lib');

const { h, ui, mx, wait } = R;
const s = 'r09_video_both_second_device';
const opened = [];

async function main() {
  R.refuseIfNotLocal();
  h.refuseIfAnotherRunIsLive();
  const roomLp = R.rooms().learner_calltester;
  const roomId = R.fullRoomId(roomLp);
  await R.ensureSubscriptions({ learner: true, calltester: true });
  await R.waitNoLiveCall(['learnerFirstDevice', 'calltester'], roomId);
  const L1 = await R.openP('learnerFirstDevice', roomLp, 9791, { wav: R.fixture('learner') });
  opened.push(L1);
  const L2 = await R.openP('learnerSecondDevice', roomLp, 9792, { wav: R.fixture('learner2') });
  opened.push(L2);
  const P = await R.openP('calltester', roomLp, 9793, { wav: R.fixture('peer') });
  opened.push(P);
  const LEARNER = L1.userId;

  const call = await R.placeAndAnswer(s, P, null, roomId, { answer: false });
  if (!call) return R.finish(s, opened);
  let d1 = null;
  for (let i = 0; i < 15 && !d1; i++) {
    await ui.clickBanner(L1.page, 'answer').catch(() => {});
    await wait(2000);
    const devs = await mx.liveMembershipDevices(L1.token, roomId, LEARNER);
    if (devs.length === 1) d1 = devs[0];
  }
  h.check(s, 'device one answered', !!d1, 'no learner membership');
  if (!d1) return R.finish(s, opened);
  const answeredAt = Date.now();
  await R.cameraOn(s, P);
  await R.cameraOn(s, L1);
  await wait(25000);

  let d2 = null;
  for (let i = 0; i < 8 && !d2; i++) {
    await h.ensureRoom(L2, roomLp);
    await ui.clickControl(L2.page, 'call').catch(() => {});
    for (let j = 0; j < 6 && !d2; j++) {
      await wait(2000);
      d2 = (await mx.liveMembershipDevices(L1.token, roomId, LEARNER)).find((d) => d !== d1) || null;
    }
  }
  h.check(s, 'the same call opened on device two', !!d2, 'no second learner membership');
  if (!d2) return R.finish(s, opened);

  let prompt1 = false;
  let prompt2 = false;
  let left = null;
  // Both devices watched for a few seconds before choosing; a device's own
  // prompt buttons are part of its prompt.
  const buttons = [...R.L('callDevicesUseThis'), ...R.L('callDevicesLeaveHere')];
  const hasButtons = async (p) => (await ui.labels(p.page).catch(() => [])).some((x) => buttons.includes(x));
  for (let i = 0; i < 15 && !left; i++) {
    prompt1 = prompt1 || await hasButtons(L1) || await R.sees(L1, 'callDevicesTitle', `prompt1-${i}`);
    prompt2 = prompt2 || await hasButtons(L2) || await R.sees(L2, 'callDevicesTitle', `prompt2-${i}`);
    if (prompt2 && (prompt1 || i >= 3)) left = await R.clickText(L2, 'callDevicesLeaveHere', `leave-${i}`);
    if (!left) await wait(1500);
  }
  await R.dumpLabels(L1, 'prompt');
  await R.dumpLabels(L2, 'prompt');
  h.check(s, 'device one is told the call is open on two devices (#9168)', prompt1, 'no "open on two of your devices" prompt on device one (labels + OCR)');
  h.check(s, 'device two is told the call is open on two devices', prompt2, 'no prompt on device two (labels + OCR)');
  h.check(s, 'device two pressed "Leave the call here"', !!left, 'no "Leave the call here" control (labels + OCR)');
  if (!left) {
    console.log('   (no choice was made: ending the call from the peer)');
    await R.hangUp(s, P, roomId);
    return R.finish(s, opened, { callKey: call.callKey, d1, d2, aborted: 'no Leave the call here' });
  }
  await wait(10000);
  const liveNow = await mx.liveMembershipDevices(L1.token, roomId, LEARNER);
  // Presence is evidence; a device's absence from one state write is not (the
  // harness README), so device two leaving is asked as "not listed live" AND
  // its page no longer showing the call.
  const d2Panel = await ui.labels(L2.page).catch(() => null);
  if (!d2Panel || !d2Panel.length) h.skipped(s, 'device two left the call', 'device two\'s screen could not be read');
  else h.check(s, 'device two left the call', !liveNow.includes(d2) && !d2Panel.some((x) => /hang up/i.test(x)), `live devices ${liveNow.join(',')}; device two still shows hang up: ${d2Panel.some((x) => /hang up/i.test(x))}`);
  const still1 = liveNow.includes(d1);
  h.check(s, 'device one carries on in the call', still1, 'device one is no longer in the call');
  const after1 = await R.dumpLabels(L1, 'after-leave');
  const after1Text = await R.ocr(L1, 'after-leave');
  if (after1Text == null) h.skipped(s, "device one's prompt withdrew", 'device one could not be read');
  else h.check(s, "device one's prompt withdrew", !R.anyLabel(after1, 'callDevicesTitle') && !R.ocrHas(after1Text, R.EN('callDevicesTitle')), 'prompt still up on device one');
  await wait(30000);
  const callSeconds = Math.round((Date.now() - answeredAt) / 1000);
  await R.hangUp(s, L1, roomId);

  await R.watchLoading(s, P, { doneAlready: async () => (await R.related(P.token, roomId, call.callKey, R.MERGED)).length >= 1 });
  const got = await R.collect(P.token, roomId, call.callKey, { halves: 2, audio: 2, merged: 1, settleS: 300 });
  R.save('events.json', { callKey: call.callKey, d1, d2, transcripts: got.transcripts.map(R.summarise), audio: got.audio.map(R.summarise), merged: got.merged.map(R.summarise) });
  const learnerEvents = [...got.audio, ...got.transcripts].filter((e) => e.sender === LEARNER);
  h.check(s, "every learner recording and half names its device (so device two's silence is checkable)", learnerEvents.every((e) => typeof e.content?.device_id === 'string' && e.content.device_id),
    `${learnerEvents.filter((e) => !e.content?.device_id).length} learner event(s) without device_id`);
  const fromD2 = learnerEvents.filter((e) => e.content?.device_id === d2);
  h.check(s, 'the device that left writes no half and no recording', fromD2.length === 0, `${fromD2.length} event(s) from device two: ${fromD2.map((e) => e.type).join(',')}`);
  const merged = R.assertTranscriptCriteria(s, got, [{ p: L1, words: R.WORDS.learner }, { p: P, words: R.WORDS.peer }], { anySubscribed: true });
  await R.assertPlays(s, P.token, merged, callSeconds);
  const scP = { name: P.name, ...(await R.readTranscriptScreen(P)) };
  const scL = { name: L1.name, ...(await R.readTranscriptScreen(L1)) };
  R.assertScreens(s, [scP, scL], { subscribed: [scP, scL], unsubscribed: [], anySubscribed: true, callSeconds });
  await R.checkCreditOnce(s, [L1, P], [call.ring?.event_id, call.callKey,
    ...(await R.eventsSince(P.token, roomId, call.mark, [mx.CALL])).map((e) => e.event_id)].filter(Boolean), call.ringAt - 60000);
  const cards = mx.cardsIn(await R.eventsSince(P.token, roomId, call.mark, [mx.CALL]), P.userId);
  h.check(s, 'the call left exactly one card, answered', cards.length === 1 && cards[0].answered, JSON.stringify(cards));
  await R.confirmSubscriptions(s, { learner: true, calltester: true });
  return R.finish(s, opened, { callKey: call.callKey, d1, d2 });
}

main().catch(R.fatal(s, opened));

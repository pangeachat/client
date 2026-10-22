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

  const call = await R.placeAndAnswer(s, P, null, roomId, { video: true, answer: false });
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
  await wait(30000);

  let d2 = null;
  for (let i = 0; i < 8 && !d2; i++) {
    await h.ensureRoom(L2, roomLp);
    await ui.clickControl(L2.page, 'videoCall').catch(() => ui.clickControl(L2.page, 'call').catch(() => {}));
    for (let j = 0; j < 6 && !d2; j++) {
      await wait(2000);
      d2 = (await mx.liveMembershipDevices(L1.token, roomId, LEARNER)).find((d) => d !== d1) || null;
    }
  }
  h.check(s, 'the same call opened on device two', !!d2, 'no second learner membership');
  if (!d2) return R.finish(s, opened);

  let prompt1 = false;
  let prompt2 = false;
  for (let i = 0; i < 10 && !(prompt1 && prompt2); i++) {
    await wait(2000);
    prompt1 = prompt1 || R.anyLabel(await ui.labels(L1.page).catch(() => []), 'callDevicesTitle');
    prompt2 = prompt2 || R.anyLabel(await ui.labels(L2.page).catch(() => []), 'callDevicesTitle');
  }
  await R.dumpLabels(L1, 'prompt');
  await R.dumpLabels(L2, 'prompt');
  h.check(s, 'device one is told the call is open on two devices (#9168)', prompt1, 'no "open on two of your devices" prompt on device one');
  h.check(s, 'device two is told the call is open on two devices', prompt2, 'no prompt on device two');

  const leaveHere = new Set(R.L('callDevicesLeaveHere'));
  let left = false;
  for (let i = 0; i < 10 && !left; i++) {
    const l = await ui.labels(L2.page).catch(() => []);
    const label = l.find((n) => leaveHere.has(n));
    if (label) {
      const r = await ui.findRect(L2.page, label, { exact: true }).catch(() => null);
      if (r) { await L2.page.mouse.click(r.x, r.y); left = true; }
    }
    if (!left) await wait(2000);
  }
  h.check(s, 'device two pressed "Leave the call here"', left, 'no "Leave the call here" control');
  await wait(10000);
  const still1 = (await mx.liveMembershipDevices(L1.token, roomId, LEARNER)).includes(d1);
  h.check(s, 'device one carries on in the call', still1, 'device one is no longer in the call');
  const after1 = await R.dumpLabels(L1, 'after-leave');
  h.check(s, "device one's prompt withdrew", !R.anyLabel(after1, 'callDevicesTitle'), 'prompt still up on device one');
  await wait(30000);
  const callSeconds = Math.round((Date.now() - answeredAt) / 1000);
  await R.hangUp(s, L1, roomId);

  await R.watchLoading(s, P);
  const got = await R.collect(P.token, roomId, call.callKey, { halves: 2, audio: 2, merged: 1, settleS: 300 });
  R.save('events.json', { callKey: call.callKey, d1, d2, transcripts: got.transcripts.map(R.summarise), audio: got.audio.map(R.summarise), merged: got.merged.map(R.summarise) });
  const fromD2 = [...got.audio, ...got.transcripts].filter((e) => e.sender === LEARNER && e.content?.device_id === d2 && R.spoken(e).trim().length + (e.type === R.AUDIO ? 1 : 0) > 0);
  h.check(s, 'the device that left writes no half and no recording', fromD2.length === 0, `${fromD2.length} event(s) from device two: ${fromD2.map((e) => e.type).join(',')}`);
  const merged = R.assertTranscriptCriteria(s, got, [{ p: L1, words: R.WORDS.learner }, { p: P, words: R.WORDS.peer }], { anySubscribed: true });
  await R.assertPlays(s, P.token, merged, callSeconds);
  const scP = { name: P.name, ...(await R.readTranscriptScreen(P)) };
  const scL = { name: L1.name, ...(await R.readTranscriptScreen(L1)) };
  R.assertScreens(s, [scP, scL], { subscribed: [scP, scL], unsubscribed: [], anySubscribed: true });
  await R.checkCreditOnce(s, [L1, P], [call.ring?.event_id, call.callKey,
    ...(await R.eventsSince(P.token, roomId, call.mark, [mx.CALL])).map((e) => e.event_id)].filter(Boolean), call.ringAt - 60000);
  await R.confirmSubscriptions(s, { learner: true, calltester: true });
  return R.finish(s, opened, { callKey: call.callKey, d1, d2 });
}

main().catch(R.fatal(s, opened));

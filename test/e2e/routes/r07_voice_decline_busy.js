// Route 7 (pangeachat/2-step-choreographer#3350): voice, one subscribed,
// DECLINE and BUSY. client#9458 (call-ended / busy tones not cut off),
// client#9166 (ringtone before decline).
//
// Part 1: learner (subscribed) calls calltester, who declines.
// Part 2: calltester is on a call with routes_es; learner calls calltester and
//         is declined automatically as busy.
//
// Tones are asked of the page's own media elements (every play / pause /
// ended is recorded from before the app loads): a tone that was paused within
// half a second of starting was cut off. A page that played no media element
// at all for a tone leaves the check unasked (SKIP), never passed.
const R = require('./lib');

const { h, ui, mx, wait } = R;
const s = 'r07_voice_decline_busy';
const opened = [];

function tonesAfter(media, t0) {
  const ev = (media || []).filter((m) => m.t >= t0);
  const plays = ev.filter((m) => m.kind === 'play');
  return plays.map((p) => {
    const end = ev.find((m) => m.t > p.t && m.src === p.src && (m.kind === 'pause' || m.kind === 'ended'));
    return { src: p.src, playedMs: end ? end.t - p.t : null, how: end ? end.kind : 'still playing', dur: p.dur };
  });
}

async function main() {
  R.refuseIfNotLocal();
  h.refuseIfAnotherRunIsLive();
  const rooms = R.rooms();
  const roomLp = rooms.learner_calltester;
  const roomId = R.fullRoomId(roomLp);
  const esLp = rooms.es_calltester;
  const esRoomId = R.fullRoomId(esLp);
  await R.ensureSubscriptions({ learner: true, calltester: false, routes_es: false });
  await R.waitNoLiveCall(['learner', 'calltester'], roomId);
  await R.waitNoLiveCall(['routes_es', 'calltester'], esRoomId);

  const A = await R.openP('learner', roomLp, 9771, { wav: R.fixture('learner') });
  opened.push(A);
  const B = await R.openP('calltester', roomLp, 9772, { wav: R.fixture('peer') });
  opened.push(B);

  console.log('[1] decline');
  const t0 = Date.now();
  const call = await R.placeAndAnswer(s, A, B, roomId, { answer: false });
  if (!call) return R.finish(s, opened);
  await wait(4000);
  const declined = await h.actUntil('decline', () => ui.clickBanner(B.page, 'decline'),
    async () => (await h.since(A.token, roomId, call.mark)).some((e) => e.type === mx.DECLINE && e.sender === B.userId));
  h.check(s, 'the callee declined (decline event)', declined, 'no decline event');
  const tDecline = Date.now();
  await wait(8000);
  const evs = await R.eventsSince(A.token, roomId, call.mark);
  const dec = evs.find((e) => e.type === mx.DECLINE && e.sender === B.userId);
  h.check(s, 'the decline points at the ring it answers', dec?.content?.['m.relates_to']?.event_id === call.ring.event_id,
    JSON.stringify(dec?.content?.['m.relates_to']));
  const cardsA = mx.cardsIn(evs, A.userId);
  const cardsB = mx.cardsIn(await R.eventsSince(B.token, roomId, call.mark), B.userId);
  h.check(s, 'one declined card, the same on both sides', cardsA.length === 1 && cardsA[0].declined && cardsB.length === 1 && cardsB[0].id === cardsA[0].id,
    JSON.stringify({ cardsA, cardsB }));
  h.check(s, 'a declined call writes no transcript and no recording',
    !evs.some((e) => [R.TRANSCRIPT, R.AUDIO, R.MERGED].includes(e.type)), evs.map((e) => e.type).join(','));
  const mediaA = await R.saveParticipant(A);
  const mediaB = await R.saveParticipant(B);
  const ring = tonesAfter(mediaB, t0).filter((x) => x.playedMs == null || x.playedMs > 0);
  if (!mediaB) h.skipped(s, 'the callee heard a ringtone before declining (#9166)', 'media log unreadable');
  else h.check(s, 'the callee heard a ringtone before declining (#9166)', ring.length > 0, `media: ${JSON.stringify(mediaB).slice(0, 300)}`);
  const ended = tonesAfter(mediaA, tDecline - 1000);
  if (!ended.length) h.skipped(s, "the caller's call-ended tone is not cut off (#9458)", `no media element played on the caller after the decline: ${JSON.stringify(mediaA).slice(-300)}`);
  else h.check(s, "the caller's call-ended tone is not cut off (#9458)", ended.every((x) => x.playedMs == null || x.playedMs >= 500 || x.how === 'ended'), JSON.stringify(ended));

  console.log('[2] busy');
  await h.recover(A, roomLp);
  await B.browser.close().catch(() => {});
  opened.splice(opened.indexOf(B), 1);
  const E = await R.openP('routes_es', esLp, 9773, { wav: R.fixture('es_mix') });
  opened.push(E);
  const B2 = await R.openP('calltester', esLp, 9772, { wav: R.fixture('peer') });
  opened.push(B2);
  const first = await R.placeAndAnswer(s, E, B2, esRoomId);
  if (!first) return R.finish(s, opened);
  await wait(5000);
  const tBusy = Date.now();
  const second = await R.placeAndAnswer(s, A, null, roomId, { answer: false });
  if (!second) return R.finish(s, opened);
  let busy = null;
  for (let i = 0; i < 15 && !busy; i++) {
    await wait(2000);
    busy = (await h.since(A.token, roomId, second.mark)).find((e) => e.type === mx.DECLINE && e.sender === B2.userId);
  }
  h.check(s, 'a ring to someone already in a call is declined as busy', busy?.content?.reason === 'busy',
    busy ? JSON.stringify(busy.content) : 'no decline at all');
  await wait(3000);
  const onA = await R.dumpLabels(A, 'busy');
  h.check(s, 'the caller is told the other person is busy', R.anyLabel(onA, 'callFailedBusy'), 'no "busy" text on the caller');
  const mediaA2 = await R.saveParticipant(A);
  const busyTone = tonesAfter(mediaA2, tBusy);
  if (!busyTone.length) h.skipped(s, 'the busy tone is not cut off (#9458)', 'no media element played on the caller after the busy decline');
  else h.check(s, 'the busy tone is not cut off (#9458)', busyTone.every((x) => x.playedMs == null || x.playedMs >= 500 || x.how === 'ended'), JSON.stringify(busyTone));
  const stillFirst = await mx.hasMembership(E.token, esRoomId, E.userId) && await mx.hasMembership(B2.token, esRoomId, B2.userId);
  h.check(s, 'the call already in progress was not disturbed', stillFirst, 'a membership of the first call went away');
  await R.hangUp(s, E, esRoomId);
  const busyCards = mx.cardsIn(await R.eventsSince(A.token, roomId, second.mark), A.userId);
  R.save('events.json', { decline: dec, cardsA, cardsB, busy, busyCards });
  h.check(s, 'the busy attempt leaves one card, not answered', busyCards.length === 1 && !busyCards[0].answered, JSON.stringify(busyCards));
  return R.finish(s, opened);
}

main().catch(R.fatal(s, opened));

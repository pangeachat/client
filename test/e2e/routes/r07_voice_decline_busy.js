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
const closed = [];

function tonesAfter(media, t0) {
  const ev = (media || []).filter((m) => m.t >= t0);
  const plays = ev.filter((m) => m.kind === 'playing');
  return plays.map((p) => {
    const end = ev.find((m) => m.t > p.t && m.src === p.src && (m.kind === 'pause' || m.kind === 'ended'));
    return { src: p.src, startedAt: p.t, playedMs: end ? end.t - p.t : null, endAt: end ? end.at : null, how: end ? end.kind : 'still playing', dur: p.dur };
  });
}

/// A tone is cut off when it stopped before most of it played: the file's own
/// duration where the element knew it, else half a second.
// Still playing when read (null) is a tone that never finished: not ok.
// Judged on the media clock (where playback stood when it stopped), not wall
// time: a stalled tone paused early has played little however long it sat.
const cutOk = (x) => x.playedMs != null && (x.how === 'ended'
  || (Number.isFinite(x.dur) && x.dur > 0 && Number.isFinite(x.endAt) && x.endAt >= 0.8 * x.dur));
const RINGTONE = /\/(phone|call)\.(mp3|ogg)/;
const ENDED_TONE = /\/call_ended\.(mp3|ogg)/;
// The engaged tone is notification.ogg played twice (ring_player.dart).
const BUSY_TONE = /\/notification\.(mp3|ogg)/;

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
  if (!call) return R.finish(s, opened, { closed });
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
  h.check(s, 'one declined card, the same on both sides', cardsA.length === 1 && cardsA[0].declined && cardsB.length === 1 && cardsB[0].id === cardsA[0].id && cardsB[0].declined,
    JSON.stringify({ cardsA, cardsB }));
  // The caller's device writes an EMPTY half (zero chunks) for a call that never
  // connected; whether it should is not settled by the design docs, so it is
  // recorded as evidence rather than judged. What must not exist is a
  // recording or words.
  R.save('halves-for-unanswered-call.json', evs.filter((e) => e.type === R.TRANSCRIPT).map(R.summarise));
  h.check(s, 'a declined call saves no recording and transcribes nothing',
    !evs.some((e) => [R.AUDIO, R.MERGED].includes(e.type) || (e.type === R.TRANSCRIPT && R.spoken(e).trim())),
    evs.map((e) => e.type).join(','));
  const mediaA = await R.saveParticipant(A);
  const mediaB = await R.saveParticipant(B);
  const ring = tonesAfter(mediaB, t0).filter((x) => RINGTONE.test(x.src) && x.startedAt <= tDecline);
  if (!mediaB) h.skipped(s, 'the callee heard a ringtone before declining (#9166)', 'media log unreadable');
  else h.check(s, 'the callee heard a ringtone before declining (#9166)', ring.length > 0, `media: ${JSON.stringify(mediaB).slice(0, 300)}`);
  const ended = tonesAfter(mediaA, tDecline - 1000).filter((x) => ENDED_TONE.test(x.src));
  if (!ended.length) h.skipped(s, "the caller's call-ended tone is not cut off (#9458)", `no media element played on the caller after the decline: ${JSON.stringify(mediaA).slice(-300)}`);
  else h.check(s, "the caller's call-ended tone is not cut off (#9458)", ended.every(cutOk), JSON.stringify(ended));

  console.log('[2] busy');
  await h.recover(A, roomLp);
  await B.browser.close().catch(() => {});
  opened.splice(opened.indexOf(B), 1);
  closed.push(B);
  const E = await R.openP('routes_es', esLp, 9773, { wav: R.fixture('es_mix') });
  opened.push(E);
  const B2 = await R.openP('calltester', esLp, 9772, { wav: R.fixture('peer') });
  opened.push(B2);
  const first = await R.placeAndAnswer(s, E, B2, esRoomId);
  if (!first) return R.finish(s, opened, { closed });
  await wait(5000);
  const tBusy = Date.now();
  const second = await R.placeAndAnswer(s, A, null, roomId, { answer: false });
  if (!second) return R.finish(s, opened, { closed });
  // The busy decline and the caller's "<name> is on another call" are asked
  // together, sampling the caller's screen (labels, then OCR of the canvas)
  // from the moment the ring goes out: the notice may be brief.
  let busy = null;
  let told = false;
  for (let i = 0; i < 12 && !(busy && told); i++) {
    if (!busy) busy = (await h.since(A.token, roomId, second.mark)).find((e) => e.type === mx.DECLINE && e.sender === B2.userId);
    if (!told) {
      const l = await ui.labels(A.page).catch(() => []);
      told = l.some((x) => /is on another call/i.test(x)) || R.ocrHas(await R.ocr(A, `busy-${i}`), 'is on another call');
    }
    if (!(busy && told)) await wait(1500);
  }
  h.check(s, 'a ring to someone already in a call is declined as busy', busy?.content?.reason === 'busy',
    busy ? JSON.stringify(busy.content) : 'no decline at all');
  await R.dumpLabels(A, 'busy');
  h.check(s, 'the caller is told the other person is on another call', told, 'no "<name> is on another call" on the caller (labels + OCR, ~18s)');
  await wait(6000); // let a tone that is still sounding finish before judging it
  const mediaA2 = await R.saveParticipant(A);
  const busyTone = tonesAfter(mediaA2, tBusy).filter((x) => BUSY_TONE.test(x.src));
  if (!busyTone.length) h.skipped(s, 'the busy tone is not cut off (#9458)', 'no media element played on the caller after the busy decline');
  else h.check(s, 'the busy tone plays twice, neither cut off (#9458)', busyTone.length === 2 && busyTone.every(cutOk), JSON.stringify(busyTone));
  const stillFirst = await mx.hasMembership(E.token, esRoomId, E.userId) && await mx.hasMembership(B2.token, esRoomId, B2.userId);
  h.check(s, 'the call already in progress was not disturbed', stillFirst, 'a membership of the first call went away');
  await R.hangUp(s, E, esRoomId);
  const busyCards = mx.cardsIn(await R.eventsSince(A.token, roomId, second.mark), A.userId);
  R.save('events.json', { decline: dec, cardsA, cardsB, busy, busyCards });
  h.check(s, 'the busy attempt leaves one card, not answered', busyCards.length === 1 && !busyCards[0].answered, JSON.stringify(busyCards));
  return R.finish(s, opened, { closed });
}

main().catch(R.fatal(s, opened));

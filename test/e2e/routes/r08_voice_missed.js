// Route 8 (pangeachat/2-step-choreographer#3350): voice, one subscribed,
// MISSED -- the ring runs out. client#9166 (ringtone audible), missed-call
// handling: the ring stops on its own, both sides get one "missed" card, no
// transcript or recording is written.
const R = require('./lib');

const { h, mx, wait } = R;
const s = 'r08_voice_missed';
const opened = [];

async function main() {
  R.refuseIfNotLocal();
  h.refuseIfAnotherRunIsLive();
  const roomLp = R.rooms().learner_calltester;
  const roomId = R.fullRoomId(roomLp);
  await R.ensureSubscriptions({ learner: true, calltester: false });
  await R.waitNoLiveCall(['learner', 'calltester'], roomId);
  const A = await R.openP('learner', roomLp, 9781, { wav: R.fixture('learner') });
  opened.push(A);
  const B = await R.openP('calltester', roomLp, 9782, { wav: R.fixture('peer') });
  opened.push(B);

  const t0 = Date.now();
  const call = await R.placeAndAnswer(s, A, B, roomId, { answer: false });
  if (!call) return R.finish(s, opened);
  await wait(8000);
  const ringing = await R.dumpLabels(B, 'ringing');
  h.check(s, 'the callee is shown the incoming call', ringing.some((l) => /answer/i.test(l)) || R.anyLabel(ringing, 'callAnswer'), 'no answer control on the callee');
  // The ring lives 30s (never more than 90); wait well past it.
  await wait(50000);
  const evs = await R.eventsSince(A.token, roomId, call.mark);
  const cardsA = mx.cardsIn(evs, A.userId);
  const cardsB = mx.cardsIn(await R.eventsSince(B.token, roomId, call.mark), B.userId);
  R.save('events.json', { ring: call.ring, cardsA, cardsB, types: evs.map((e) => e.type) });
  h.check(s, 'one missed card, the same on both sides', cardsA.length === 1 && !cardsA[0].answered && !cardsA[0].declined
    && cardsB.length === 1 && cardsB[0].id === cardsA[0].id && !cardsB[0].answered && !cardsB[0].declined, JSON.stringify({ cardsA, cardsB }));
  // Never joined at any point: no membership state from the callee since the mark.
  const bJoins = evs.filter((e) => e.type === 'com.famedly.call.member' && e.sender === B.userId && Array.isArray(e.content?.memberships) && e.content.memberships.length);
  h.check(s, 'the callee never joined', bJoins.length === 0 && !(await mx.hasMembership(B.token, roomId, B.userId)), `${bJoins.length} callee membership write(s)`);
  h.check(s, 'the caller is no longer in a call', !(await mx.hasMembership(A.token, roomId, A.userId)), 'caller still holds a membership after the ring ran out');
  const after = await R.dumpLabels(B, 'after-ring');
  const answerNames = R.L('callAnswer');
  h.check(s, 'the ring is gone from the callee after it ran out', !after.some((l) => /answer/i.test(l) || answerNames.includes(l)), 'answer control still on screen');
  // The caller's device writes an EMPTY half (zero chunks) for a call that never
  // connected; whether it should is not settled by the design docs, so it is
  // recorded as evidence rather than judged. What must not exist is a
  // recording or words.
  R.save('halves-for-unanswered-call.json', evs.filter((e) => e.type === R.TRANSCRIPT).map(R.summarise));
  h.check(s, 'a missed call saves no recording and transcribes nothing',
    !evs.some((e) => [R.AUDIO, R.MERGED].includes(e.type) || (e.type === R.TRANSCRIPT && R.spoken(e).trim())),
    evs.map((e) => e.type).join(','));
  const media = await R.saveParticipant(B);
  const plays = (media || []).filter((m) => m.t >= t0 && m.t <= t0 + 45000 && m.kind === 'playing' && /\/(phone|call)\.(mp3|ogg)/.test(m.src));
  if (!media) h.skipped(s, 'the callee heard a ringtone (#9166)', 'media log unreadable');
  else h.check(s, 'the callee heard a ringtone (#9166)', plays.length > 0, 'no media element played on the callee while it rang');
  return R.finish(s, opened);
}

main().catch(R.fatal(s, opened));

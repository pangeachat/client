// TWO DEVICES OF ONE ACCOUNT IN ONE CALL.
//
// `transcript.js` proves what two PEOPLE end up with. This proves what one
// person ends up with when they are signed in twice -- the case a transcript
// half used to be destroyed by, and the one case a hand-driven test cannot
// reach at all, because it takes three browsers and two of them have to be the
// same account.
//
// WHAT USED TO HAPPEN. A half was keyed by the SENDER. Two of a learner's
// devices in one call wrote two halves that nothing could tell apart, so the
// reader kept ONE of them and presented it -- with its own accounting, which
// said it was complete -- as the whole of what that person said. The other
// device's speech was destroyed silently. That is worse than a refused send:
// a refusal is visible.
//
// The fix keys a half by DEVICE and MERGES an account's halves, and the unit
// tests for it pass. That is not the same claim as this file's. A unit test
// hands `assembleTranscript` two candidates it built itself; nothing before
// this ran a second real client, on a real homeserver, and asked whether two
// halves are what actually reaches the room.
//
// FOUR THINGS, and each is asked of the SERVER or of the SCREEN, never of the
// click that was supposed to cause it.
//
//   1. BOTH HALVES SURVIVE. Two `pangea.call_transcript` events from the ONE
//      account, carrying DIFFERENT device ids -- and those two ids are the two
//      devices the server itself says were in the call.
//   2. THE TRANSACTION IDS DIFFER. Same call, same sender, different device.
//      Computed here from what is on the wire, with the app's own formula, so
//      the check fails if a half reaches the room without a device id.
//   3. THE READER MERGED THEM. Read off the app's own read-time log, which
//      states how many devices a half was assembled from -- the one place the
//      count is visible, and unconditional there by design.
//   4. NOTHING IS LOST. Every word any half carries is on the screen
//      afterwards, and nobody who spoke is reported as having said nothing.
//
// WHAT THE PRODUCT DOES THAT SHAPES THIS FILE.
//
// `CaptureElection` means the two devices do NOT normally both record: they
// rank themselves by device id and exactly one of them holds the recording,
// so the ordinary outcome is one half with speech and one half with none. That
// is not a weaker case than two speaking halves -- it is the SHARPER one. The
// half that gets dropped when a reader keeps only one is as likely to be the
// full one as the empty one, and dropping it turns a learner who talked for a
// minute into a learner the screen says was silent.
//
// Which device wins is a coin toss on a random device id, and the loser may
// also DESTROY what it captured before the handover, so both outcomes are
// asserted for and neither is assumed. When both halves carry speech the
// "nothing is lost" check gets its full form; when only one does, it keeps the
// form the run can honestly support and the rest is declared INCONCLUSIVE
// rather than quietly passed.
//
// AND GETTING TWO DEVICES INTO ONE CALL AT ALL IS ITS OWN FINDING. The ring
// flow will not do it: `answeredOnAnotherDevice` dismisses the second device's
// prompt the moment the first one's membership lands, deliberately, so once one
// device has answered the other is offered no way in. The only route left is
// the one the product's own code names -- the convergence race, both devices
// answering in the same instant -- so that is what step [2] drives, and it
// retries the RACE rather than the click.
const h = require('./harness');
const { ui, mx, wait } = h;
const labels = require('./labels');

/// One machine-shaped setting this file needs and `config.js` does not carry:
/// which of the two devices leaves at the handover. See where it is read.
const env = (name, fallback) => process.env[name] || fallback;

const { room: ROOM, roomId: ROOM_ID, shot, accounts } = h.cfg;

/// The transcript relation, as the writer sends it.
const TRANSCRIPT = 'pangea.call_transcript';

/// The call membership state event, one per account, listing that account's
/// devices in the call.
const MEMBER = 'com.famedly.call.member';

/// The app's own transaction id, computed from what arrived.
///
/// A COPY of `CallTranscriptContent.txnId`, and it has to be: the id is never
/// sent back down, so the only way to ask whether two halves would have
/// collided is to rebuild the key the writer built and compare. Kept in the
/// same shape as the Dart, empty segment and all, so a change there that this
/// file did not follow shows up as a check that stops meaning what it says.
///
/// `usableDeviceId` in the app refuses an empty id and anything past 255
/// characters; absent, empty and over-long all key ALIKE, which is the whole
/// point -- so they all reduce to the empty segment here too.
const txnIdOf = (ev) => {
  const raw = ev?.content?.device_id;
  const device =
    typeof raw === 'string' && raw.length > 0 && raw.length <= 255 ? raw : '';
  return `pangea.call_transcript:${ev?.content?.call_key}:${ev?.sender}:${device}`;
};

/// The words in a half, flattened.
function spoken(ev) {
  const segs = ev?.content?.segments;
  if (!Array.isArray(segs)) return '';
  return segs.map((s) => (s && typeof s.text === 'string' ? s.text : '')).join(' ');
}

/// Words of four letters or more, lowercased. A SET, for the reason
/// `transcript.js` gives: the provider decides its own punctuation and casing.
function words(text) {
  return new Set(
    text
      .toLowerCase()
      .split(/[^\p{L}\p{N}]+/u)
      .filter((w) => w.length >= 4),
  );
}

/// A distinctive word from each fixture.
///
/// THREE fixtures, because there are three microphones: the learner's two
/// devices and the other person's. The first two sets are what makes this file
/// able to say which of the learner's DEVICES a word came from -- and without
/// that, a reader that merged both halves and a reader that kept one are the
/// same screen.
///
/// EIGHT words a side rather than four, because the device that records second
/// only ever holds part of the call: its fixture repeats the same eight
/// sentences three times over, so whichever stretch it held carries some of
/// these. One is enough.
///
/// They move with the wavs. `config.js` says where those come from and the
/// README says how to make them; replace a fixture and this list moves with it,
/// or a run passes on a transcript of different audio.
const DEVICE_ONE_SAYS = [
  'compass', 'orchard', 'trumpet', 'glacier',
  'pelican', 'saffron', 'marble', 'thunder',
];
const DEVICE_TWO_SAYS = [
  'lantern', 'bicycle', 'harbor', 'november',
  'cinnamon', 'walnut', 'ferry', 'meadow',
];
const PEER_SAYS = ['course', 'orange', 'quarter', 'gardens'];

/// How long the survivor holds the call by itself after the handover.
///
/// Named because a check below quotes it: "captured nothing in the forty
/// seconds it held the call alone" is only a finding next to the number.
const HANDOVER_TAIL_MS = 40000;

/// The language every fixture is in. See `transcript.js`: speech-to-text is
/// asked for the SPEAKER'S OWN target language, so an account learning
/// something else has this English audio come back EMPTY rather than wrong --
/// and an empty half is exactly what this file is trying to tell a real merge
/// failure apart from.
const FIXTURE_LANG = 'en';

/// Refuses a run whose fixtures the accounts cannot be understood in.
///
/// Asked over its own API logins, BEFORE the browsers, on the same terms
/// `transcript.js` asks it: the alternative is three browsers and a two-minute
/// call to arrive at a conclusion only the account's settings could give.
async function refuseIfNotLearning(names) {
  for (const name of names) {
    const a = accounts[name];
    const { token, userId } = await mx.login(a.user, a.pass);
    let code;
    try {
      code = await mx.targetLanguage(token, userId);
    } finally {
      // A session taken for one question is a Matrix DEVICE, and in THIS file
      // a stray device of the learner account is not merely untidy -- it is a
      // third candidate in the election the scenario is about.
      await mx.logout(token);
    }
    if (mx.baseLang(code) === FIXTURE_LANG) continue;
    throw new Error(
      `${name} (${userId}) is learning ${code || 'nothing yet'}, and the `
      + `fixtures are ${FIXTURE_LANG}. Their half would come back empty however `
      + 'well the call went, and an empty half is the thing this scenario has '
      + 'to be able to tell a real merge failure apart from. Sign in as that '
      + `account and set the learning language to ${FIXTURE_LANG}.`,
    );
  }
}

/// Refuses two devices that would say the same thing.
///
/// Two microphones playing one file write two halves nobody can tell apart --
/// which is the exact shape of the merge failure this file exists to catch, so
/// every check would pass hardest at the moment the feature was most broken.
/// A refusal rather than a check, on the terms `browser.js` refuses a missing
/// wav: it is a fact about the rig, and naming the app for it would be a lie.
function refuseIfTheDevicesShareAVoice() {
  const fs = require('fs');
  const one = accounts.learnerFirstDevice.wav;
  const two = accounts.learnerSecondDevice.wav;
  if (one !== two && fs.existsSync(one) && fs.existsSync(two)) {
    const a = fs.readFileSync(one);
    const b = fs.readFileSync(two);
    if (!a.equals(b)) return;
  }
  throw new Error(
    `the learner's two devices would play the same audio (${one} and ${two}). `
    + 'Two halves of identical speech are indistinguishable, so a reader that '
    + 'kept one of them would pass every check in this file. Point '
    + 'CALL_LEARNER_TWO_WAV at a DIFFERENT wav of real English speech, containing '
    + `the words ${DEVICE_TWO_SAYS.join('/')} and none of `
    + `${DEVICE_ONE_SAYS.join('/')}.`,
  );
}

/// The transcript halves written since a mark. Read from the SERVER, and
/// identified by the harness's own since-a-mark mechanism rather than by
/// counting -- see `transcript.js` for why counting was wrong.
async function halvesSince(token, mark) {
  const events = await h.since(token, ROOM_ID, mark);
  return events.filter((e) => e.type === TRANSCRIPT);
}

/// Halves already in the room under [callKey], written before [before].
///
/// Asked of the room's history rather than of this run, because the thing it
/// is looking for is a call key an EARLIER call already used -- and an earlier
/// call may be one nobody here placed.
async function halvesUnder(token, callKey, before) {
  const events = await mx.timeline(token, ROOM_ID, 300);
  return events.filter(
    (e) => e.type === TRANSCRIPT
      && e.content?.call_key === callKey
      && (e.origin_server_ts || 0) < before,
  );
}

/// Which of the learner's devices JOINED this call, according to the server.
///
/// The union over every membership event the account wrote since the ring, and
/// NOT the current state -- which under-reports, measured here rather than
/// assumed. `com.famedly.call.member` is one state event per ACCOUNT holding a
/// list of that account's devices, so two devices answering in the same instant
/// each write the whole list from their own view: at 02:11:31.811 the second
/// device published a list containing only itself, and seven milliseconds later
/// the first published a list containing only ITSELF, and the room state kept
/// the later one. Both devices really were in the call -- both wrote a
/// transcript half for it -- while the state said one.
///
/// So the state is a snapshot that a race can lie in, and the timeline is the
/// record. Both are read: a device whose event has aged out of the window is
/// still in the state, and a device the state has lost is still in the
/// timeline.
async function joinedDevices(token, userId, mark) {
  const ids = new Set();
  for (const e of await h.since(token, ROOM_ID, mark)) {
    if (e.type !== MEMBER || e.sender !== userId) continue;
    for (const m of e.content?.memberships ?? []) {
      if (typeof m?.device_id === 'string' && m.device_id) ids.add(m.device_id);
    }
  }
  for (const d of await mx.liveMembershipDevices(token, ROOM_ID, userId)) {
    ids.add(d);
  }
  return [...ids];
}

/// Opens the transcript of the NEWEST call card on screen.
///
/// `ui.clickControl` ranks its matches by whether a click can reach them and
/// takes the first, which is right for a control there is only one of. A
/// timeline holds a "Read the transcript" for EVERY call the room has ever had,
/// and the one a click could reach turned out to be a call from months back --
/// so the dialog opened, the check that a card offers the transcript passed,
/// and every word of the call under test was reported missing from a screen
/// that was never showing it.
///
/// The newest card is the LOWEST one: the timeline is bottom-anchored and the
/// room opens at the end of it. So the choice here is by position rather than
/// by rank, and it is made from the same scan every other click uses --
/// hittable only, for the reason [ui.choose] gives: a card scrolled out of the
/// list keeps a node at a coordinate that can sit over something else entirely.
async function openNewestTranscript(page) {
  const candidates = labels.candidates('transcriptLink');
  const nodes = (await ui.scan(page)).filter(
    (n) => n.hittable && n.names.some((name) => candidates.includes(name)),
  );
  if (!nodes.length) return false;
  const lowest = nodes.reduce((a, b) => (b.y > a.y ? b : a));
  await page.mouse.click(lowest.x, lowest.y);
  return true;
}

/// Captures a page's console.
///
/// The app states how many devices a half was assembled from in its read-time
/// log and NOWHERE ELSE -- deliberately, because the multi-device fact must
/// never displace a specific true cause in front of a learner. So the log is
/// the only place this scenario can ask its third question, and it is a real
/// answer: the same line a bug report would be diagnosed from.
function captureConsole(participant) {
  const lines = [];
  participant.page.on('console', (m) => {
    try {
      lines.push(m.text());
    } catch (_) {
      // A diagnostic is never worth a dropped run.
    }
  });
  return lines;
}

/// Every browser this run launched, so nothing has to be in scope to close it.
///
/// The top-level catch is the reason: a throw anywhere leaves three Chromes
/// holding three profile locks, and the NEXT run then fails at its first line
/// with a message about the harness rather than about whatever went wrong here.
const opened = [];

/// Ends the run with nothing left running.
///
/// Chrome holds an exclusive lock on a profile directory, so a scenario that
/// exits over a browser it launched leaves the NEXT run dead at its first
/// line -- "the browser is already running for ..." -- which reads as a broken
/// harness rather than as the previous failure it actually is. Every screenshot
/// and every log this file keeps is written before it gets here, so nothing
/// diagnostic is lost by closing.
async function finish(participants, code) {
  for (const p of participants) {
    if (!p) continue;
    await p.browser.close().catch(() => {});
  }
  process.exit(code);
}

async function main() {
  const s = 'transcript-two-devices';
  console.log('[1] three browsers: the learner TWICE, and the other person');
  h.refuseIfAnotherRunIsLive();
  refuseIfTheDevicesShareAVoice();
  await refuseIfNotLearning(['learner', 'calltester']);

  // ALL THREE opened before anything rings, and that ordering is not
  // cosmetic. A ring lives thirty seconds. Opening the second device once the
  // call is already up would spend most of that window signing a browser in,
  // and the run would then report a product that refuses a second device when
  // what really happened is that the harness answered an EXPIRED ring.
  const A1 = await h.openParticipant('learnerFirstDevice', ROOM, 9741);
  opened.push(A1);
  const A2 = await h.openParticipant('learnerSecondDevice', ROOM, 9742);
  opened.push(A2);
  const B = await h.openParticipant('calltester', ROOM, 9743);
  opened.push(B);
  const logA1 = captureConsole(A1);
  const logA2 = captureConsole(A2);

  // The two accounts, named once. A1 and A2 are ONE account, so every
  // server-side question about "the learner" is asked with one token.
  const LEARNER = A1.userId;

  // Nothing of the learner's may be in a call before this one starts. A live
  // membership left behind by an earlier run is a THIRD device in the
  // election, and it would answer this scenario's central question with a
  // number that is nothing to do with what it drove.
  const before = await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER);
  h.check(s, 'the learner starts with no device in a call', before.length === 0,
    `already in a call on ${before.length} device(s): ${before.join(', ')}`);
  if (before.length) { h.report(); await finish([A1, A2, B], 2); }

  console.log('[2] the peer calls, and BOTH learner devices answer at once');
  // WHY AT ONCE, and it is a fact about the product rather than a trick.
  //
  // The caller's own devices are not rung -- `shouldRing` drops a notification
  // whose sender is this account -- so the learner cannot be the one to place
  // it. The peer calls, both of the learner's devices ring, and then:
  // ANSWERING ON ONE STOPS THE OTHER. `answeredOnAnotherDevice` watches this
  // account's own call membership, and the moment a sibling's lands the other
  // device's prompt is dismissed. That is deliberate and it is the right
  // behaviour for a phone and a laptop ringing together -- but it means the
  // ring flow offers a second device NO WAY IN once the first has answered.
  //
  // So the state this file is about is reached exactly the way the product's
  // own code says it is reached: the convergence race that
  // `CaptureElection.discardsCapturedAudio` is written for -- "two of a
  // learner's devices answering the same call in the same instant each see a
  // roster that momentarily lacks the other". Both taps go out together, ahead
  // of the sync round trip that would put the second prompt away.
  //
  // A race is retried as a RACE. Once one device has joined, the other's
  // prompt is gone and no amount of clicking brings it back, so a failed
  // attempt is torn all the way down and the call is placed again.
  const attempts = 4;
  let inCall = [];
  let callKey = null;
  let attemptsUsed = 0;
  let reusedKey = null;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    attemptsUsed = attempt;
    // Retried against the RING EVENT rather than against the click, which is
    // the suite's idiom: a call button pressed while a previous teardown is
    // still settling does nothing at all, with no error anywhere.
    const markRing = await h.mark(B.token, ROOM_ID);
    const rang = await h.actUntil(
      'place call',
      async () => {
        await h.ensureRoom(B, ROOM);
        await ui.clickControl(B.page, 'call').catch(() => {});
      },
      async () => (await h.since(B.token, ROOM_ID, markRing)).some(
        (e) => e.type === mx.RING && e.sender === B.userId,
      ),
      { tries: 4, gap: 4000 },
    );
    h.check(s, `the peer placing a call rang the learner (attempt ${attempt})`,
      rang, 'no ring event reached the room');
    if (!rang) { h.report(); await finish([A1, A2, B], 2); }

    // WHICH CALL THIS IS, straight off the ring. The call key is the caller's
    // membership event id, and the ring carries it as its reference -- so it is
    // knowable the moment the call starts, rather than only once a half has
    // been written under it. Everything this scenario reads later is scoped to
    // it.
    const ring = (await h.since(B.token, ROOM_ID, markRing))
      .find((e) => e.type === mx.RING && e.sender === B.userId);
    callKey = ring?.content?.['m.relates_to']?.event_id ?? null;

    // Both taps in flight together. PROVEN by the memberships, never by the
    // clicks: the ring banner is an overlay Flutter keeps out of the
    // accessibility tree, so it is driven positionally and a click that missed
    // looks exactly like one that worked.
    await Promise.all([
      ui.clickBanner(A1.page, 'answer').catch(() => {}),
      ui.clickBanner(A2.page, 'answer').catch(() => {}),
    ]);
    for (let i = 0; i < 12; i++) {
      inCall = await joinedDevices(A1.token, LEARNER, markRing);
      if (inCall.length >= 2) break;
      await wait(1000);
    }
    // A call key this room has already written a half under is a call whose
    // transcript is destroyed before it is written -- see [freshCallKey]. There
    // is nothing to learn from such a call, so the race is run again; the fact
    // that it happened is remembered and reported below rather than retried
    // away.
    const earlier = callKey
      ? await halvesUnder(A1.token, callKey, ring?.origin_server_ts ?? 0)
      : [];
    if (earlier.length) reusedKey = { callKey, earlier: earlier.length, attempt };
    if (inCall.length >= 2 && !earlier.length) break;

    console.log(`   (attempt ${attempt}: ${inCall.length} of the learner's ` +
      `devices got in${earlier.length ? ', and the call key was already used' : ''}` +
      '; tearing the call down and racing again)');
    // All the way down, and PROVEN down. A half-joined call left standing would
    // have the next ring suppressed as busy on one device and answered on the
    // other -- and, worse, a caller that never retracted its membership hands
    // the next call the SAME call key, which is the silent destroyer below.
    for (const p of [A1, A2, B]) {
      await h.actUntil(
        `teardown hangup for ${p.name}`,
        () => ui.clickPanel(p.page, 'hangup').then(() => {}, () => {}),
        async () => (p === B
          ? !(await mx.hasMembership(p.token, ROOM_ID, p.userId))
          : (await mx.liveMembershipDevices(p.token, ROOM_ID, LEARNER)).length === 0),
        { tries: 4, gap: 2500 },
      );
    }
    // And SETTLED. The caller anchors the next call on its own membership event
    // id, read from its local room state, so a call placed before the retract
    // has echoed back reuses the id the last call used.
    await wait(10000);
  }

  h.check(s, 'BOTH of the learner devices are in the one call',
    inCall.length >= 2,
    `the server saw ${inCall.length} of the learner's devices join ` +
      `(${inCall.join(', ') || 'none'}) across ${attemptsUsed} attempt(s). ` +
      'Nothing after this can be asked at all: one device in a call writes ' +
      'one half, and one half is what the keying this replaced already ' +
      'produced. What the second device said about the ring is in the log ' +
      'written below');

  // The silent destroyer, reported whether or not a later attempt got round it.
  //
  // The transcript transaction id is `(call key, sender, device)`, and this
  // homeserver collapses a repeated transaction id from the SAME device: the
  // second send returns the first event and writes nothing. So two calls that
  // share a call key are two calls of which only the FIRST has a transcript --
  // silently, with no error anywhere, and the second call's speech simply never
  // reaches the room.
  //
  // It is not hypothetical and it is not this file's doing: it was measured
  // here, on a redial two seconds after a hangup, where the caller rang with the
  // PREVIOUS call's membership event id. Reported as a failure rather than
  // retried away, because a scenario that quietly re-rolls until it gets a clean
  // call would hide exactly the thing a real-stack run is for.
  h.check(s, 'this call has a call key no earlier call already wrote under',
    reusedKey === null,
    reusedKey
      ? `attempt ${reusedKey.attempt} rang with call key ${reusedKey.callKey}, ` +
        `which ${reusedKey.earlier} earlier half/halves in this room already ` +
        'carry. Every writer in that call computes the transaction id it ' +
        'already used, the homeserver hands back the earlier event, and the ' +
        'whole of that call\'s transcript is lost with nothing logged'
      : '');

  if (inCall.length < 2) {
    await A1.page.screenshot({ path: shot('two-devices-nojoin-one.png') }).catch(() => {});
    await A2.page.screenshot({ path: shot('two-devices-nojoin-two.png') }).catch(() => {});
    // The second device's own account of what it did with the ring. Without
    // it, "a second device never joined" is a symptom with no cause attached,
    // and the two causes -- a tap that missed an overlay, and a prompt the app
    // deliberately put away -- want completely different fixes.
    const said = logA2.filter((l) => /ring|call|answer/i.test(l));
    console.log('   the second device said:');
    for (const line of said.slice(-15)) console.log(`     ${line}`);
    require('fs').writeFileSync(
      shot('two-devices-nojoin.log'),
      [...logA1, '', '=== second device ===', ...logA2].join('\n'),
    );
    console.log(`   (full log: ${shot('two-devices-nojoin.log')})`);
    h.report();
    await finish([A1, A2, B], 2);
  }
  console.log(`   (both devices in the call after ${attemptsUsed} attempt(s): ` +
    `${inCall.join(', ')}; call key ${callKey})`);

  // A SECOND mark, taken now rather than at the top. A race that had to be
  // retried placed a call that was torn down, and a torn-down call writes its
  // halves too -- so "two halves from the learner" would be satisfied by one
  // half from each of two DIFFERENT calls, which is the keying this file is
  // supposed to be able to refuse. Halves are written at the end of a call, so
  // everything this call produces is after this line.
  const mCall = await h.mark(A1.token, ROOM_ID);

  console.log('[3] talking, then a HANDOVER: one device leaves, the other records');
  // WHY A HANDOVER, and it is forced by the product rather than chosen.
  //
  // `CaptureElection` lets exactly ONE of an account's devices hold the
  // recording: they rank themselves by device id and the loser stands aside, so
  // two devices sitting in a call together produce one half with speech and one
  // with none. That is a real case and the checks above cover it -- but it
  // cannot tell a reader that MERGED the two halves from one that kept the
  // half with the words in it and threw the empty one away. Both draw the same
  // screen.
  //
  // Speech in BOTH halves is what separates them, and the only way to get it is
  // for the device holding the recording to leave: the election re-runs, the
  // survivor takes over, and the two halves then carry different stretches of
  // the same call. That is also a flow a learner really has -- picking the call
  // up on a phone and closing the laptop.
  //
  // Which device holds the recording is decided by a device id neither this
  // file nor anyone else chooses, so the leaver is A1 and the run says which
  // case it got. When A1 was the recorder, the last check below gets its full
  // form; when it was not, A1 recorded nothing, the run is the one-speaker case
  // again, and that check is declared inconclusive rather than quietly passed.
  await wait(35000);

  // WHICH device leaves. It has to be the one holding the recording for the
  // handover to put speech in both halves, and which one that is comes down to
  // a device id neither this file nor anybody else chooses --
  // `CaptureElection` ranks on it, lowest first. The harness cannot ask a
  // browser which Matrix device it is (the app keeps no such thing anywhere a
  // page can read), so the pairing is only knowable by hanging one up and
  // seeing which id goes.
  //
  // So the choice is a setting rather than a guess, and it selects which
  // DEVICE leaves -- never what is asserted about the result. Persistent
  // profiles keep their device ids, so on any one machine the same value keeps
  // landing on the same side: if a run keeps reporting the handover
  // inconclusive, it is leaving the passenger, and this is the knob.
  const leaverName = env('CALL_HANDOVER_DEVICE', 'one') === 'two' ? 'two' : 'one';
  const leaver = leaverName === 'two' ? A2 : A1;
  console.log(`   device ${leaverName} leaves; the other should pick the recording up`);
  const beforeHandover = await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER);
  const handed = await h.actUntil(
    `device ${leaverName} leaves mid-call`,
    () => ui.clickPanel(leaver.page, 'hangup').then(() => {}, () => {}),
    async () => {
      const now = await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER);
      return now.length > 0 && now.length < Math.max(beforeHandover.length, 2);
    },
    { tries: 4, gap: 3000 },
  );
  const stillIn = await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER);
  console.log(`   (after the handover the call holds ${JSON.stringify(stillIn)})`);
  h.check(s, 'one device left and the other stayed in the call', handed,
    `the learner holds ${JSON.stringify(stillIn)} -- either the device that ` +
      'was told to leave never did, or both did, and neither leaves the ' +
      'survivor recording a stretch of its own');

  // Long enough for the survivor's own fixture to be transcribed. Its wav
  // repeats the same sentences three times over precisely so that this
  // stretch -- whichever stretch it turns out to be -- has words in it.
  await wait(HANDOVER_TAIL_MS);

  console.log('[4] the rest of the call ends, then the drain settles');
  // ASKED OF THE ACCOUNT, not of each device, and that is forced by the shape
  // of the state rather than chosen. `com.famedly.call.member` is one row per
  // ACCOUNT, so "did THIS device leave" is not a question it can answer: the
  // row that remains says the account is still in the call, and it says the
  // same thing whichever device is left. A first version asked it per device
  // and failed on a hangup that had plainly worked -- the count it compared
  // against was itself a snapshot of a race (see [joinedDevices]).
  //
  // Both taps every round, retried against the account's memberships being
  // gone. Clicking a hangup that has already happened is harmless; a device
  // still in the call after five rounds is not.
  const learnerLeft = await h.actUntil(
    'hang up both learner devices',
    async () => {
      await ui.clickPanel(A1.page, 'hangup').catch(() => {});
      await ui.clickPanel(A2.page, 'hangup').catch(() => {});
    },
    async () =>
      (await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER)).length === 0,
    { tries: 5, gap: 3000 },
  );
  h.check(s, 'both learner devices left the call', learnerLeft,
    'the learner still holds ' +
      `${(await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER)).length} ` +
      'live membership(s), so at least one device never hung up and its half ' +
      'has not been written yet');
  await h.actUntil(
    'hangup on the peer',
    () => ui.clickPanel(B.page, 'hangup'),
    async () => !(await mx.hasMembership(B.token, ROOM_ID, B.userId)),
  );

  // The halves are written after the drain, not at hangup, so this waits for
  // the SERVER to have them rather than sleeping a guessed interval. Three are
  // expected -- two devices of the learner and one of the peer -- and the loop
  // waits for the third rather than stopping at two, so "two halves" is never
  // satisfied by one learner half plus the peer's.
  let written = [];
  for (let i = 0; i < 40; i++) {
    written = await halvesSince(A1.token, mCall);
    if (written.length >= 3) break;
    await wait(3000);
  }

  console.log('[5] what reached the room');
  const mine = written.filter((e) => e.sender === LEARNER);
  const theirs = written.filter((e) => e.sender === B.userId);
  // The raw halves, kept. Every check below is a sentence about these events,
  // and a failure that cannot be re-read against the bytes that caused it is a
  // failure somebody has to reproduce before they can start on it.
  require('fs').writeFileSync(
    shot('two-devices-halves.json'),
    JSON.stringify(
      { callKey, inCall, halves: written },
      null,
      1,
    ),
  );
  console.log(`   (${written.length} half/halves: ${mine.length} learner, ` +
    `${theirs.length} peer)`);

  // Every half belongs to the SAME call. The mark above should already
  // guarantee it, and this is what says so out loud: a half from an earlier,
  // abandoned attempt would otherwise stand in for the second device's, and
  // the check below would read a keying failure as a success.
  const keys = new Set(written.map((e) => e.content?.call_key));
  h.check(s, 'every half belongs to the one call', keys.size === 1,
    `${keys.size} call key(s) among ${written.length} half/halves: ` +
      `${JSON.stringify([...keys])}`);

  // ONE. This is the assertion the whole file is for. Under the keying this
  // replaced there was one half per ACCOUNT, and the second device's speech
  // was destroyed on the way to the screen.
  h.check(s, 'the account wrote a half from EACH of its two devices',
    mine.length === 2,
    `${mine.length} half/halves from the learner, not 2` +
      (mine.length
        ? ` (devices ${mine.map((e) => JSON.stringify(e.content?.device_id)).join(', ')})`
        : ''));

  const ids = mine.map((e) => e.content?.device_id);
  const named = ids.filter((d) => typeof d === 'string' && d.length > 0);
  h.check(s, 'each half NAMES the device that wrote it',
    named.length === mine.length && mine.length > 0,
    `device ids on the wire: ${JSON.stringify(ids)} -- a half that names no ` +
      'device keys alike with every other half that named none, which is the ' +
      'grouping the fix exists to break');
  h.check(s, 'the two halves name DIFFERENT devices',
    new Set(named).size === mine.length && mine.length > 0,
    `device ids on the wire: ${JSON.stringify(ids)}`);

  // And those are the devices that were actually in the call. Two distinct ids
  // are not enough on their own: a writer inventing them, or naming a device
  // from a previous call, would satisfy the check above and be a worse bug
  // than the one it replaced.
  h.check(s, 'the halves name the devices the server saw in the call',
    named.length > 0 && named.every((d) => inCall.includes(d)),
    `halves name ${JSON.stringify(named)}; the call had ` +
      `${JSON.stringify(inCall)}`);

  // TWO. Same call, same sender, different device -- so the two sends carry
  // different transaction ids. Computed from what is on the wire with the
  // app's own formula, so a half that arrived with no device id fails here
  // even when two events happen to have landed.
  const txns = mine.map(txnIdOf);
  h.check(s, 'the two halves would be sent under DIFFERENT transaction ids',
    new Set(txns).size === mine.length && mine.length > 0,
    `both computed to ${JSON.stringify(txns[0])} -- one key for two devices, ` +
      'so a resend collapse and a second device are the same event to the ' +
      'server');

  // And they are two events, not one. The distinct ids above are a statement
  // about the KEY; this is the outcome, and the two are worth asking
  // separately because only the second is what a person would notice.
  // Guarded on there BEING halves, and the guard is not decoration: a run that
  // produced none passed this check, because no events are trivially distinct.
  // That is a check that passes hardest when the feature is most broken, which
  // is the one shape this suite refuses.
  h.check(s, 'the two halves are two distinct events',
    mine.length > 0 && new Set(mine.map((e) => e.event_id)).size === mine.length,
    `event ids: ${JSON.stringify(mine.map((e) => e.event_id))}`);

  // AND THE SURVIVOR RECORDED THE REST OF IT.
  //
  // The handover is only a handover if the device that stayed picked the
  // recording up: `CaptureElection` re-runs whenever the roster changes, and
  // with its only sibling gone the survivor ranks first and records. A survivor
  // that captured NOTHING means the learner went on talking into a call that
  // nobody was recording, for as long as the call lasted.
  //
  // Asked only when a device really did leave one behind, and asked of the
  // COUNTS rather than of the words: a survivor that captured chunks and could
  // not transcribe them is a different failure from one that never opened a
  // recorder at all, and only the counts tell them apart.
  const survivorHalf = handed
    ? mine.find((e) => stillIn.includes(e.content?.device_id))
    : null;
  if (!handed) {
    h.skipped(s, 'the device that stayed recorded the rest of the call',
      'no handover happened, so no device was left to take the recording over');
  } else if (!survivorHalf) {
    // A half naming no device cannot be matched to the device that stayed.
    // That is the pre-keying world, where this question is unanswerable by
    // construction -- and saying so is the point rather than a gap.
    h.skipped(s, 'the device that stayed recorded the rest of the call',
      `a device did stay (${stillIn.join(', ')}), but no half names a device ` +
        `(${JSON.stringify(mine.map((e) => e.content?.device_id))}), so which ` +
        'half is the survivor\'s cannot be established at all');
  } else {
    const captured = survivorHalf.content?.chunks_captured ?? 0;
    h.check(s, 'the device that stayed recorded the rest of the call',
      captured > 0,
      `the surviving device ${survivorHalf.content?.device_id} captured ` +
        `${captured} chunk(s) in the ${HANDOVER_TAIL_MS / 1000}s it held the ` +
        'call alone, and refused nothing (captureRefused ' +
        `${survivorHalf.content?.capture_refused}, lost ` +
        `${survivorHalf.content?.chunks_lost}, dropped ` +
        `${survivorHalf.content?.capture_dropped_ms}ms). Everything said after ` +
        'the other device left went unrecorded. NOTE the one local condition ' +
        'that could explain it: this stack\'s LiveKit token lacks ' +
        'CanUpdateOwnMetadata, and the app says so itself -- "the recorder ' +
        'election is running without its capability layer" is in the log ' +
        'written below on every run here');
  }

  console.log('[6] which device said what');
  const byDevice = new Map();
  for (const e of mine) byDevice.set(e.content?.device_id ?? '<none>', words(spoken(e)));
  for (const [device, w] of byDevice) {
    console.log(`   ${device}: ${w.size} word(s) -- ${[...w].slice(0, 10).join(' ')}`);
  }
  const allMine = new Set([...byDevice.values()].flatMap((w) => [...w]));
  // Which device's fixture ended up where. The two learner devices play
  // DIFFERENT audio precisely so this is answerable at all -- without it, a
  // half from the wrong device and a half from the right one are the same
  // event.
  const spokeOne = DEVICE_ONE_SAYS.filter((w) => allMine.has(w));
  const spokeTwo = DEVICE_TWO_SAYS.filter((w) => allMine.has(w));
  console.log(`   device one's fixture: ${JSON.stringify(spokeOne)}; ` +
    `device two's: ${JSON.stringify(spokeTwo)}`);
  const halvesWithWords = mine.filter((e) => words(spoken(e)).size > 0);

  // A run where NEITHER learner device transcribed anything cannot judge the
  // rest, and must say so rather than passing: an empty screen is consistent
  // with a perfect merge of two empty halves.
  const canJudgeWords = halvesWithWords.length > 0;
  h.check(s, 'at least one learner device transcribed what it heard',
    canJudgeWords,
    'both halves came back with no words at all, so nothing after this can ' +
      'tell a merge that kept everything from one that kept nothing. Check ' +
      'the fixtures reached Chrome and that speech-to-text answered');

  console.log('[7] and what the screen says about it');
  // WHAT CAN BE READ OFF THIS SCREEN, AND WHAT CANNOT.
  //
  // The transcript panel is drawn by CanvasKit, and a turn's WORDS reach
  // neither the accessibility tree nor the page text: measured here, with the
  // panel plainly showing six sentences while `document.body.innerText` and
  // every `flt-semantics` name between them carried none of them. A check
  // written on the words is therefore a check that can only ever fail, and one
  // written on their absence -- "nobody who spoke is reported as silent" -- is
  // a check that can only ever pass. This file had both, and neither was
  // saying anything.
  //
  // What DOES reach the tree is every turn's own timestamp, one per drawn
  // segment, and all of them: Flutter does not clip its semantics to a scroll
  // view, so a turn below the fold is still in the tree. Counting them asks
  // the question this file actually needs -- was every turn either device
  // wrote drawn -- and it can fail, because a reader that kept one half draws
  // that half's turns and no others.
  await h.ensureRoom(A1, ROOM);
  // The semantics tree is thrown away with the document on any navigation, and
  // a tree that is not there answers "no card" for a card that is.
  await ui.enableSemantics(A1.page).catch(() => {});
  const card = await ui.hasControl(A1.page, 'transcriptLink').catch(() => false);
  const seen = card ? [] : await ui.labels(A1.page).catch(() => []);
  h.check(s, 'the card offers the transcript', card,
    'no way in to the transcript from the call card; on screen: ' +
      JSON.stringify((Array.isArray(seen) ? seen : []).slice(0, 25)));

  let turnsDrawn = 0;
  let dialogOpen = false;
  if (card) {
    await openNewestTranscript(A1.page);
    await wait(6000);
    await A1.page.screenshot({ path: shot('two-devices-transcript.png') }).catch(() => {});
    // The dialog's own title, from the page TEXT rather than from a label --
    // `transcript.js` reads its consent notice the same way and for the same
    // reason. Prose is not required to be in the accessibility tree, and this
    // one happens to be there.
    const text = await A1.page
      .evaluate(() => document.body.innerText || '')
      .catch(() => '');
    const titles = labels.labelsFor('callTranscriptTitle').filter(Boolean);
    dialogOpen = titles.some((t) => text.includes(t));
    turnsDrawn = (await ui.scan(A1.page))
      .flatMap((n) => n.names)
      .filter((name) => /^\d{1,2}:\d{2}$/.test(name.trim()))
      .length;
    // Kept, because "the screen drew four turns and the room holds nineteen"
    // is a sentence somebody has to be able to check, and a screenshot cannot
    // be grepped.
    require('fs').writeFileSync(
      shot('two-devices-panel.txt'),
      `${(await ui.labels(A1.page)).join(' | ')}\n\n=== page text ===\n${text}`,
    );
  }
  h.check(s, 'the transcript dialog opened', dialogOpen,
    'the panel never appeared, so nothing below is a statement about the ' +
      'product. The labels and the page text are in the file named above');

  // THE ASSERTION THE READER HALF OF THIS FIX EXISTS FOR.
  //
  // Every turn every half carries has to be drawn. A reader that grouped by
  // sender keeps ONE of an account's halves, so the screen is short by exactly
  // the number of turns the half it dropped was carrying -- which is what this
  // counts. When the dropped half is empty, as it is whenever
  // `CaptureElection` stood a device aside for the whole call, nothing is lost
  // and this correctly passes; when it is not, nothing else here notices.
  const segmentsWritten = written.reduce(
    (n, e) => n + (e.content?.segments?.length ?? 0),
    0,
  );
  const learnerSegments = mine.reduce(
    (n, e) => n + (e.content?.segments?.length ?? 0),
    0,
  );
  const droppableSegments = mine
    .map((e) => e.content?.segments?.length ?? 0)
    .sort((a, b) => a - b)[0] ?? 0;
  if (!dialogOpen) {
    h.skipped(s, 'every turn either device wrote is drawn',
      'the panel never opened, so what it drew says nothing');
  } else if (droppableSegments === 0) {
    // Stated rather than passed over. Both halves are still there, still named
    // by device and still merged -- the checks in [5] say so -- but with one of
    // them empty this count cannot tell a merge from a reader that kept the
    // other one, and claiming it could would be the one thing this suite must
    // never do.
    h.skipped(s, 'every turn either device wrote is drawn',
      `one of the learner's halves carries no turns (${mine
        .map((e) => `${e.content?.device_id}:${e.content?.segments?.length ?? 0}`)
        .join(', ')}), so a reader that dropped it would draw the same screen ` +
      'as one that merged it. CaptureElection stands a device aside for as ' +
      'long as a sibling is holding the recording, so this is the ordinary ' +
      'outcome; the handover in [3] is what makes it otherwise, and it only ' +
      'does when the device that left was the one recording');
  } else {
    h.check(s, 'every turn either device wrote is drawn',
      turnsDrawn >= segmentsWritten,
      `${turnsDrawn} turn(s) drawn for ${segmentsWritten} written ` +
        `(${learnerSegments} of them the learner's, across ` +
        `${mine.length} device(s): ${mine
          .map((e) => `${e.content?.device_id}=${e.content?.segments?.length ?? 0}`)
          .join(', ')}). A reader that keeps one of an account's halves draws ` +
        'exactly this: short by the turns of the half it dropped');
  }

  // The peer is here to make the call a call, and its half is checked only for
  // the one thing that would invalidate everything above: a merge that reached
  // across ACCOUNTS would put the peer's words under the learner and this file
  // would read it as a successful device merge.
  const peerWords = new Set(theirs.flatMap((e) => [...words(spoken(e))]));
  if (!peerWords.size || !allMine.size) {
    h.skipped(s, "the peer's speech did not end up under the learner",
      `nothing to compare: the learner has ${allMine.size} word(s), the peer ` +
        `${peerWords.size}`);
  } else {
    const crossed = PEER_SAYS.filter((w) => allMine.has(w));
    h.check(s, "the peer's speech did not end up under the learner",
      crossed.length === 0,
      `the learner's half carries the peer's words ${crossed.join(' ')} -- the ` +
        'merge crossed accounts, not devices');
  }

  console.log('[8] no unhandled errors on any of the three');
  for (const p of [A1, A2, B]) {
    h.check(s, `${p.name} had no unhandled errors`, p.errors.length === 0,
      JSON.stringify(p.errors.slice(0, 3)));
  }

  // Kept for the report: a run that failed on the screen is diagnosed from
  // what the reader said about every half, and that is not in any screenshot.
  const logPath = shot('two-devices-read.log');
  require('fs').writeFileSync(
    logPath,
    [...logA1, '', '=== second device ===', ...logA2].join('\n'),
  );
  console.log(`   (the reader's own log: ${logPath})`);

  // The exit code is the result. `h.report()` returns the failure count, and a
  // run with failed checks exiting 0 makes every promise in this header worth
  // nothing to anything that reads exit codes.
  await finish([A1, A2, B], h.report() === 0 ? 0 : 1);
}

main().catch(async (e) => {
  console.error('FAILED', e && e.message ? e.message : e);
  await finish(opened, 1);
});

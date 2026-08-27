// What the two people can READ afterwards.
//
// The rest of this suite proves a call happened: it rang, it was answered, it
// hung up, and a card says so. None of it proves the thing the call is FOR.
// Every transcript assertion here is one the other scenarios deliberately do
// not make -- device_p4 says so in as many words, skipping its recording check
// because "the transcript at the other end is what proves it, and this
// scenario does not reach it".
//
// Three things, and each fails in a way nothing else here would catch.
//
// CONSENT. The notice is a promise made to the person before they are
// recorded. It is product copy, not decoration, and it can be lost to a layout
// change with every other check in this suite still green.
//
// ATTRIBUTION. This is the one a person cannot test by hand. One laptop has
// one microphone, so a hand-driven call records the same room twice and both
// halves come back identical -- exactly the shape a crossed-wires bug
// produces. The harness gives each browser its OWN wav, so the two halves
// carry provably different speech and "did each person's words land under
// THEIR name" becomes a question that can be asked at all.
//
// HONESTY. A half that failed is not a person who said nothing. The screen has
// four separate things to say -- they spoke / they were silent / they wrote
// nothing / we could not find out -- and the whole feature is built around
// never printing one when another is true. So this asserts that nobody is
// called silent when they spoke, which is the wrong answer that hurts most.
const h = require('./harness');
const { ui, mx, wait } = h;
const labels = require('./labels');

const { room: ROOM, roomId: ROOM_ID, shot } = h.cfg;

/// The transcript relation, as the writer sends it.
const TRANSCRIPT = 'pangea.call_transcript';

/// The transcript halves written SINCE a mark.
///
/// Read from the SERVER rather than the screen, like every other assertion in
/// this suite, and identified by the harness's own since-a-mark mechanism
/// rather than by counting.
///
/// Counting was the obvious way and it was wrong. A fixed timeline window
/// holds the last N events, and a single call adds thirty-odd membership
/// events -- so older halves slide out of the window as the new ones arrive,
/// the count barely moves, and "everything after the first N" comes back
/// empty. It reported zero halves for a call that had written them, which
/// reads exactly like a dead feature.
async function halvesSince(token, mark) {
  const events = await h.since(token, ROOM_ID, mark);
  return events.filter((e) => e.type === TRANSCRIPT);
}

/// The words in a half, flattened.
function spoken(ev) {
  const segs = ev?.content?.segments;
  if (!Array.isArray(segs)) return '';
  return segs.map((s) => (s && typeof s.text === 'string' ? s.text : '')).join(' ');
}

/// Words of four letters or more, lowercased, accents intact.
///
/// Compared as a SET rather than as a string: the provider decides its own
/// punctuation and casing, and a test that turns on those fails for a reason
/// that is not a bug.
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
/// The fixtures are ENGLISH, and deliberately so. They were Spanish, and
/// neither test account speaks Spanish -- the speech provider is told which
/// language to expect from the speaker's own profile, so Spanish audio came
/// back as a handful of nonsense words or as nothing at all, and an empty
/// transcript is indistinguishable from a broken pipeline. Audio the accounts
/// could plausibly have produced is the only kind that tests anything.
///
/// caller.wav: "Good afternoon. My name is Anna and today I want to tell you
///              about my journey to Seville."
/// callee.wav: "Of course. Please tell me everything about Seville. I was
///              there last year in autumn."
///
/// The shared word ("Seville") is deliberately NOT used to tell them apart.
/// If the fixtures are replaced these move with them, and the run says so
/// loudly rather than passing on a transcript of different audio.
const CALLER_SAYS = ['afternoon', 'journey'];
const CALLEE_SAYS = ['course', 'autumn'];

async function main() {
  const s = 'transcript';
  console.log('[1] two browsers, each with its own voice');
  h.refuseIfAnotherRunIsLive();
  const A = await h.openParticipant('learner', ROOM, 9731);
  const B = await h.openParticipant('calltester', ROOM, 9732);

  const mA = await h.mark(A.token, ROOM_ID);

  console.log('[2] a call, long enough for the chunker to cut and ship');
  // Retried against the RING EVENT, not against the click: a call button
  // pressed while the previous teardown is still settling does nothing at
  // all, with no error anywhere. This is the suite's own idiom.
  const rang = await h.actUntil(
    'place call',
    async () => {
      await h.ensureRoom(A, ROOM);
      await ui.clickControl(A.page, 'call').catch(() => {});
    },
    async () => (await h.since(A.token, ROOM_ID, mA)).some(
      (e) => e.type === mx.RING && e.sender === A.userId,
    ),
    { tries: 4, gap: 4000 },
  );
  h.check(s, 'placing a call rang the other side', rang, 'no ring event reached the room');
  if (!rang) { h.report(); process.exit(2); }

  // PROVEN by the membership it must produce, not by the click landing. The
  // banner is an overlay Flutter does not put in the accessibility tree, so
  // it is driven positionally and a click that missed looks identical to one
  // that worked -- which is why the rest of this suite never trusts one.
  const joined = await h.actUntil(
    'answer',
    () => ui.clickBanner(B.page, 'answer'),
    () => mx.hasMembership(B.token, ROOM_ID, B.userId),
  );
  h.check(s, 'answering actually joined the call', joined,
    'the callee never published a call membership');
  if (!joined) { h.report(); process.exit(2); }
  await wait(6000);

  // The consent notice belongs to the moment BEFORE the recording is read
  // back, so it is asked for here rather than at the end. Read from the page
  // TEXT: it is a line of prose in the panel, not a control, and prose is not
  // required to appear in the accessibility tree.
  const panelText = (await A.page.evaluate(() => document.body.innerText || ''))
    .replace(/\s+/g, ' ');
  const notices = labels.labelsFor('callRecordingNotice')
    .map((t) => t.split('.')[0].trim())
    .filter((t) => t.length > 12);
  h.check(s, 'the recording notice is shown to the caller',
    notices.some((t) => panelText.includes(t)),
    `no consent notice while recording; on screen: ${panelText.slice(0, 180)}`);

  // Long enough that both fixtures have spoken and the chunker has cut. Any
  // shorter and an empty transcript would mean "we did not wait", which is
  // not a result.
  await wait(30000);

  console.log('[3] hanging up, then letting the drain settle');
  // The panel's controls are positional too, and the hangup is PROVEN by the
  // membership going away.
  const left = await h.actUntil(
    'hangup',
    () => ui.clickPanel(A.page, 'hangup'),
    async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)),
  );
  h.check(s, 'hanging up actually left the call', left,
    'the caller still holds a live membership');

  // The halves are written after the drain, not at hangup, so this waits for
  // the SERVER to have them rather than sleeping a guessed interval.
  let written = [];
  for (let i = 0; i < 40; i++) {
    written = await halvesSince(A.token, mA);
    if (written.length >= 2) break;
    await wait(3000);
  }

  h.check(s, 'both devices wrote a half', written.length >= 2,
    `only ${written.length} half/halves appeared within two minutes`);

  console.log('[4] what each half actually carries');
  const byA = written.find((e) => e.sender === A.userId);
  const byB = written.find((e) => e.sender === B.userId);
  h.check(s, 'each side wrote its OWN half', !!byA && !!byB,
    `A wrote ${!!byA}, B wrote ${!!byB}`);

  const aWords = words(spoken(byA));
  const bWords = words(spoken(byB));

  // The assertion this file exists for. Each fixture's distinctive words must
  // appear under the speaker who said them -- so a pipeline that crossed the
  // halves, or transcribed one source twice, fails here and nowhere else.
  const aHas = CALLER_SAYS.filter((w) => aWords.has(w));
  const bHas = CALLEE_SAYS.filter((w) => bWords.has(w));
  h.check(s, "the caller's words are under the CALLER", aHas.length > 0,
    `expected one of ${CALLER_SAYS.join('/')}; got ${[...aWords].slice(0, 12).join(' ')}`);
  h.check(s, "the callee's words are under the CALLEE", bHas.length > 0,
    `expected one of ${CALLEE_SAYS.join('/')}; got ${[...bWords].slice(0, 12).join(' ')}`);

  // And not each other's. Two halves that both contain everything is the
  // signature of one microphone being recorded twice, which is precisely what
  // a hand-driven test cannot tell apart from success.
  //
  // Guarded on there being words at all. Two EMPTY halves are not copies of
  // each other either, so without this the check passes hardest exactly when
  // the feature is most broken -- which is the shape of a check that cannot
  // fail, and this suite has been bitten by those before.
  const crossed = CALLEE_SAYS.some((w) => aWords.has(w))
    && CALLER_SAYS.some((w) => bWords.has(w));
  if (!aWords.size || !bWords.size) {
    h.skipped(s, 'the halves are not copies of each other',
      `nothing to compare: A has ${aWords.size} words, B has ${bWords.size}`);
  } else {
    h.check(s, 'the halves are not copies of each other', !crossed,
      'both halves carry both speakers -- one source was recorded twice');
  }

  // The turn-by-turn positions, on the wire. Without them the reader falls
  // back to the per-speaker view by design, so their absence is silent on
  // screen and this is the only place it can be caught.
  const positioned = (ev) => {
    const segs = ev?.content?.segments;
    return Array.isArray(segs) && segs.length > 0
      && segs.every((x) => x && typeof x.at_ms === 'number');
  };
  //
  // BOTH halves, because the timeline is all-or-nothing by design: the reader
  // draws a conversation only when every displayed segment of every half can
  // be placed, and falls back to the per-speaker view otherwise. Checking one
  // side would pass while the screen still cannot draw the thing this feature
  // exists for.
  const withSpeech = [byA, byB].filter((e) => e && spoken(e).trim().length);
  if (!withSpeech.length) {
    h.skipped(s, 'both halves carry turn positions',
      'no half with speech to carry them');
  } else {
    const unplaced = withSpeech.filter((e) => !positioned(e));
    h.check(s, 'both halves carry turn positions', unplaced.length === 0,
      `${unplaced.length} half/halves have speech but no at_ms: ` +
        unplaced.map((e) => e.sender).join(', '));
  }

  console.log('[5] and what the screen says about it');
  const card = await ui.hasControl(A.page, 'transcriptLink').catch(() => false);
  h.check(s, 'the card offers the transcript', card,
    'no way in to the transcript from the call card');

  if (card) {
    await ui.clickControl(A.page, 'transcriptLink').catch(() => {});
    await wait(4000);
    await A.page.screenshot({ path: shot('transcript-screen.png') }).catch(() => {});

    const onScreen = (await ui.labels(A.page)).join(' | ');

    // Nobody is called silent who spoke. The screen has four things it can
    // say and this is the one that would be a lie.
    const silentClaims = labels.labelsFor('callTranscriptSaidNothing')
      .filter((t) => t.length > 6)
      .some((t) => onScreen.includes(t));
    h.check(s, 'nobody who spoke is reported as silent', !silentClaims,
      `the transcript claims somebody said nothing: ${onScreen.slice(0, 200)}`);
  }

  console.log('[6] neither side logged an unhandled error');
  for (const p of [A, B]) {
    h.check(s, `${p.name} had no unhandled errors`, p.errors.length === 0,
      JSON.stringify(p.errors.slice(0, 3)));
  }

  h.report();
}

main().catch(async (e) => {
  console.error('FAILED', e && e.message ? e.message : e);
  process.exit(1);
});

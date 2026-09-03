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
// WHERE THIS RUNS.
//
// WHY THE WORDS USED TO COME BACK EMPTY, AND WHAT IT WAS NOT.
//
// This file spent a long stretch green on everything except the words, which
// came back as Whisper's silence hallucination ("you you"). Four theories were
// wrong before the cause was read straight off Chrome's own log -- sample
// rate, channel count, a too-confident reading of the Whisper artefact, and
// then the app's web tap, on the argument that `TrackRendererTap` reads a
// renderer and a renderer can be dead while `isRecording` is true. None of
// them. Nothing found here implicates the app's capture path at all, which is
// a narrower claim than "the app was fine" and is the one the evidence
// supports: the harness never fed it anything to capture.
//
// It was TWO facts about this harness. They are not the same failure -- the
// first silenced BOTH microphones outright, the second emptied one speaker's
// half while the other transcribed perfectly -- but they surface through the
// same check, and the second was invisible until the first was fixed:
//
//   - Chrome feeds `--use-file-for-fake-audio-capture` from the AUDIO SERVICE,
//     which runs in its own sandboxed process, and on macOS that sandbox
//     denies it the fixture. Chrome does not fail the capture over it: it logs
//     "Failed to read <path> as input to the fake device" and hands out exact
//     zeroes for the rest of the call. Measured, not inferred -- the wav choreo
//     received had 0 non-zero samples out of 611,712. `browser.js` now passes
//     `--disable-features=AudioServiceSandbox`, and that same wav comes back
//     with speech in it.
//   - Speech-to-text is asked for the SPEAKER'S OWN target language, read off
//     their profile. With the audio flowing, the callee (learning English) came
//     back with thirty-five words and the caller (learning Hindi) came back
//     with none: English audio transcribed as Hindi returns empty, not wrong.
//     `refuseIfNotLearning` below now says so before the call rather than after
//     it.
//
// Both of those are worth naming for the same reason: every check that is
// about the CALL stayed green through them. It rang, it was answered, both
// halves were written and attributed and positioned. Only the words were
// missing, which is precisely the shape that reads as a broken pipeline in the
// app.
//
// The word-level checks below are written as failures rather than skips ON
// PURPOSE, and this file exits on the failure count: a skip, or a green exit,
// would let a silent fixture quietly become permanent.
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
/// The fixtures are ENGLISH and about twenty seconds long, and both of those
/// are deliberate.
///
/// They were Spanish first, and neither test account speaks Spanish -- the
/// provider is told which language to expect from the speaker's own profile,
/// so Spanish audio came back as a couple of nonsense words. Then they were
/// five seconds long inside a thirty-five second call, and Chromium is told
/// `%noloop`, so five in six of every chunk was silence and the provider
/// returned "you you" from it. An empty or nonsense transcript is
/// indistinguishable from a broken pipeline, which is the worst thing a
/// fixture can be.
///
/// Four sentences each, with a real pause between them, so the cutter has
/// something to cut on and a call produces more than one turn.
///
/// The words below appear in ONE speaker's script and not the other's.
/// "Seville" and "autumn" are in both and are deliberately not used. If the
/// fixtures are replaced these move with them, and the run says so loudly
/// rather than passing on a transcript of different audio.
const CALLER_SAYS = ['afternoon', 'journey', 'spring', 'market'];
const CALLEE_SAYS = ['course', 'orange', 'quarter', 'gardens'];

/// The language both fixtures are in.
///
/// Stated so it can be CHECKED, because the coupling above is silent when it
/// breaks. Speech-to-text is asked for the speaker's own target language, and
/// an account learning something else has this English audio transcribed as
/// that other language -- which comes back empty, not wrong. The call still
/// rings, connects, and writes both halves, so the only symptom is a speaker
/// with no words, and that is indistinguishable from a dead capture path.
const FIXTURE_LANG = 'en';

/// Refuses a run whose fixtures the accounts cannot be understood in.
///
/// A refusal rather than a failed check, on the same terms `browser.js`
/// refuses a missing wav: the alternative is four minutes of call to arrive at
/// "expected one of afternoon/journey/spring/market; got", which names the app
/// for something only the account says.
///
/// Asked over its own API logins, BEFORE the browsers, so the refusal costs a
/// second rather than the two BROWSER logins and the whole call it would take
/// to reach the same conclusion from a participant's own token.
async function refuseIfNotLearning(names) {
  for (const name of names) {
    const a = h.cfg.accounts[name];
    const { token, userId } = await mx.login(a.user, a.pass);
    let code;
    try {
      code = await mx.targetLanguage(token, userId);
    } finally {
      // Handed back whatever the answer was. A session taken for one question
      // is a Matrix DEVICE, and these two accounts are reused forever.
      await mx.logout(token);
    }
    if (mx.baseLang(code) === FIXTURE_LANG) continue;
    throw new Error(
      `${name} (${userId}) is learning ${code || 'nothing yet'}, and the `
      + `fixtures are ${FIXTURE_LANG}. Speech-to-text is asked for the `
      + "speaker's own target language, so their half would come back empty "
      + 'however well the call went. Sign in as that account and set the '
      + `learning language to ${FIXTURE_LANG}. Going the other way is a change `
      + 'to this file and not a setting: the wavs, FIXTURE_LANG, and the '
      + 'CALLER_SAYS / CALLEE_SAYS words are one fixture set and all three move '
      + 'together.',
    );
  }
}

async function main() {
  const s = 'transcript';
  console.log('[1] two browsers, each with its own voice');
  h.refuseIfAnotherRunIsLive();
  await refuseIfNotLearning(['learner', 'calltester']);
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
  const notices = labels.labelsFor('callTranscriptSharedNotice')
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

  // Counted by SENDER, not by event. Two halves from one device is a
  // different failure -- a redelivery, or one side writing twice -- and
  // counting events called it success.
  const senders = new Set(written.map((e) => e.sender));
  h.check(s, 'both devices wrote a half', senders.size >= 2,
    `${written.length} half/halves from ${senders.size} sender(s): ` +
      [...senders].join(', '));

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
  if (!aWords.size || !bWords.size) {
    h.skipped(s, 'the halves are not copies of each other',
      `nothing to compare: A has ${aWords.size} words, B has ${bWords.size}`);
  } else {
    // Two ways one source gets recorded twice, and the fixture words catch
    // only the first. If the halves cross, each carries the other's script.
    // If the pipeline duplicates a stream, both halves carry the SAME text --
    // and when that text is gibberish there are no fixture words in it at
    // all, so a check written on those alone calls it a pass. Overlap is the
    // question that covers both.
    const crossed = CALLEE_SAYS.some((w) => aWords.has(w))
      && CALLER_SAYS.some((w) => bWords.has(w));
    const shared = [...aWords].filter((w) => bWords.has(w));
    const overlap = shared.length / Math.min(aWords.size, bWords.size);
    h.check(s, 'the halves are not copies of each other',
      !crossed && overlap < 0.8,
      crossed
        ? 'each half carries the other speaker -- the sources are crossed'
        : `the halves share ${Math.round(overlap * 100)}% of their words ` +
          `(${shared.slice(0, 8).join(' ')}) -- one source recorded twice`);
  }

  // The turn-by-turn positions, on the wire. Without them the reader falls
  // back to the per-speaker view by design, so their absence is silent on
  // screen and this is the only place it can be caught.
  // The app's own contract for a position, not merely "is a number":
  // TranscriptSegment.fromJson accepts an int, >= 0, below 2^53, and treats
  // anything else as absent. A check looser than the contract passes on
  // values the reader will refuse to place.
  const positioned = (ev) => {
    const segs = ev?.content?.segments;
    return Array.isArray(segs) && segs.length > 0
      && segs.every((x) => x && Number.isInteger(x.at_ms)
        && x.at_ms >= 0 && x.at_ms < 2 ** 53);
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
  // Back in the ROOM before asking what the room shows.
  //
  // The card is a timeline event, and the caller does not reliably end a call
  // still looking at the timeline -- this scenario spent every run reporting
  // "no way in to the transcript from the call card" while the page was
  // sitting on the activity map, where no card of any kind exists. That is a
  // harness failure wearing a product failure's clothes, and it hid the
  // silent-speaker check behind it, which is gated on the card and so had
  // never run at all. `ensureRoom` is a no-op when the room is already open.
  await h.ensureRoom(A, ROOM);
  // And the semantics tree turned back on: it is thrown away with the document
  // on any navigation, and a tree that is not there answers "no card" for a
  // card that is.
  await ui.enableSemantics(A.page).catch(() => {});
  const card = await ui.hasControl(A.page, 'transcriptLink').catch(() => false);
  // What WAS on screen, on the same argument `ui.waitForLabel` makes: a
  // missing control is only actionable next to the ones that were found.
  // Read only when it is missing, and never allowed to throw -- an argument to
  // `check` is evaluated before the check is, so a diagnostic gathered
  // unconditionally can end the run on the path where there was nothing to
  // explain.
  const seen = card ? [] : await ui.labels(A.page).catch(() => []);
  const insteadOnScreen = JSON.stringify(
    (Array.isArray(seen) ? seen : []).slice(0, 25),
  );
  h.check(s, 'the card offers the transcript', card,
    `no way in to the transcript from the call card; on screen: ${insteadOnScreen}`);

  if (card) {
    await ui.clickControl(A.page, 'transcriptLink').catch(() => {});
    await wait(4000);
    await A.page.screenshot({ path: shot('transcript-screen.png') }).catch(() => {});

    const onScreen = (await ui.labels(A.page)).join(' | ');

    // Nobody is called silent who spoke. The screen has four things it can
    // say and this is the one that would be a lie.
    // Built, not searched for.
    //
    // The app draws `callTranscriptSaidNothing` with a name substituted in,
    // so the exact sentence it would put on screen about a given person is
    // computable -- "calltester did not say anything". Asking whether THAT
    // string is present answers "is this person being called silent" with no
    // ambiguity at all.
    //
    // Three earlier versions of this check were wrong, each in a way the next
    // one inherited. Matching a guessed name failed because the screen draws a
    // display name or a localised "You", not a Matrix localpart. Counting the
    // claims could not tell a true note about the silent speaker from a false
    // one about the speaker who spoke. And a proximity window around each
    // claim accused whoever happened to be printed nearby -- in a two-line
    // transcript, that is everybody.
    //
    // "Silent" is the APP's definition: a half with no segments, which is what
    // `saidNothing` means. Counting words of four letters or more was a proxy,
    // and it called a half carrying a couple of short words silent.
    const templates = labels.templatesFor('callTranscriptSaidNothing');
    const youNames = labels.labelsFor('you');

    const lied = [];
    for (const ev of [byA, byB].filter(Boolean)) {
      const segs = ev.content?.segments;
      if (!Array.isArray(segs) || segs.length === 0) continue;   // truly silent

      const names = ev.sender === A.userId
        ? youNames
        : [await mx.displayName(A.token, ev.sender), ev.sender.slice(1).split(':')[0]];

      const accused = templates.some((t) =>
        names.filter(Boolean).some((n) =>
          onScreen.includes(t.replace(/\{[^}]*\}/g, String(n)))));
      if (accused) lied.push(ev.sender);
    }

    h.check(s, 'nobody who spoke is reported as silent', lied.length === 0,
      `the transcript says ${lied.join(', ')} said nothing, but their half ` +
        `carries segments`);
  }

  console.log('[6] neither side logged an unhandled error');
  for (const p of [A, B]) {
    h.check(s, `${p.name} had no unhandled errors`, p.errors.length === 0,
      JSON.stringify(p.errors.slice(0, 3)));
  }

  // The exit code is the result. `h.report()` returns the failure count and
  // an earlier version of this file threw it away, so a run with four failed
  // checks exited 0 -- which makes the header's promise that these are
  // FAILURES and not skips worth nothing to anything that reads exit codes.
  process.exit(h.report() === 0 ? 0 : 1);
}

main().catch(async (e) => {
  console.error('FAILED', e && e.message ? e.message : e);
  process.exit(1);
});

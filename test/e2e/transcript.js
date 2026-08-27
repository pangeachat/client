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
// WHERE THIS RUNS, AND WHERE IT DOES NOT YET PASS.
//
// Everything up to the words is green in two browsers: the ring, the answer,
// the consent notice, the hangup, both halves written, each under its own
// sender, with correct accounting. What does not come back is intelligible
// SPEECH. The fake microphone is verified good -- a getUserMedia probe reads
// peak RMS around 0.5 off these fixtures -- and the speech service is
// verified reached, so the loss is between the two, in the web capture path.
//
// call_audio_tap.dart names this hazard itself, on the renderer tap the web
// uses: the browser is free to refuse the requested rate and fall back to
// 48 kHz, and "labelling 48 kHz audio as 16 kHz does not fail loudly; it just
// transcribes as gibberish". What comes back is "you you" from twenty seconds
// of clear speech, which is gibberish.
//
// That is consistent with the known weakness of web recording that
// fix-renderer-attach exists for -- on the web a device can report
// isRecording == true with a dead or mislabelled recorder -- and with the
// fact that the transcript has only ever been demonstrated end to end on a
// PHONE, where PostEchoCancellationTap reads the audio module directly.
//
// So the word-level checks below are expected to fail in two browsers today.
// They are written as failures rather than skips ON PURPOSE: a skip would let
// this quietly become permanent, and the day the web path is fixed this file
// should go green without anybody remembering to re-enable it.
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
    // Tied to a PARTICIPANT, not searched for loose in the page. The literal
    // run of a placeholder string is generic by construction -- "did not say
    // anything" -- and asking whether that text appears anywhere would answer
    // yes to an unrelated control carrying the same words. What matters is
    // whether it is said about somebody who SPOKE.
    const spoke = [byA, byB]
      .filter((e) => e && words(spoken(e)).size)
      .map((e) => e.sender);
    const claims = labels.labelsFor('callTranscriptSaidNothing');
    const lied = spoke.filter((sender) => {
      const name = sender === A.userId ? 'you' : sender.slice(1).split(':')[0];
      return claims.some((t) => {
        const i = onScreen.indexOf(t);
        if (i < 0) return false;
        // The name sits beside the claim, on either side of it depending on
        // the language's word order.
        const around = onScreen.slice(Math.max(0, i - 60), i + t.length + 60);
        return around.toLowerCase().includes(name.toLowerCase());
      });
    });
    h.check(s, 'nobody who spoke is reported as silent', lied.length === 0,
      `the transcript says ${lied.join(', ')} said nothing, but they spoke`);
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

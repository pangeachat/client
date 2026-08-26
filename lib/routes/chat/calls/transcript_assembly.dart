import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';

/// The weight of a half: how much speech it actually carries.
///
/// This counted each DISTINCT utterance once for a while, to stop a half padded
/// with repeated text outweighing the truthful one it copied. That defence cost
/// more than it bought. People repeat themselves -- a learner saying "yes, yes"
/// is ordinary speech -- and de-duplicating made the genuine longer half tie
/// with a shorter earlier one and lose.
///
/// The padding it guarded against is not a real threat either: both candidates
/// come from the SAME Matrix account, and that account can already write
/// whatever single half it likes. Selection between one sender's own duplicates
/// was never a security boundary; it exists to survive a BUGGY writer whose
/// empty or partial half lands before the real one. Raw length does that, and
/// does not throw away speech somebody actually said.
int totalContentLength(List<TranscriptSegment> segments) =>
    segments.fold(0, (sum, segment) => sum + segment.text.length);

/// Why a speaker's half reads the way it does.
///
/// Three states, kept distinct on purpose. Someone opening a transcript is
/// asking whether a conversation happened, and "they said nothing", "their
/// words are missing" and "we stopped reading early" are three different
/// answers. Collapsing them is how a transcript lies.
enum HalfState {
  /// Their half is here and declares itself whole.
  present,

  /// Nothing was written for them. WHY is not knowable — a crash, a mute
  /// throughout, a free account whose transcription is entitlement-gated, an
  /// older app, or a failed provider. The view says only that they are not
  /// represented, and never that they were silent.
  absent,

  /// Something is here but is knowingly not all of it: the writer said so, or
  /// the reader stopped at its own ceiling.
  incomplete,
}

/// What one speaker's device wrote about the audio it captured.
///
/// These are claims by that device about its own recording, not facts the
/// reader can verify — a modified client can write anything, exactly as it can
/// for any message in the room. They are used to describe a half and to choose
/// between duplicates, never to authenticate one.
class HalfAccounting {
  final int chunksCaptured;
  final int chunksTranscribed;
  final bool truncated;
  final int segmentsOmitted;

  /// Chunks captured and then lost, which is the only count that means a gap.
  /// Silence is captured-but-not-transcribed and is NOT a gap; see the sink.
  final int chunksLost;

  /// Whether the microphone never opened at all.
  ///
  /// A speaker who was muted and a speaker we could not record both arrive
  /// here as zero chunks captured, and they are completely different facts. An
  /// empty half from a muted speaker is a real answer -- they said nothing --
  /// and is deliberately written as one. An empty half from a device whose
  /// microphone was refused is not an answer about the speaker at all; it is
  /// an answer about us.
  ///
  /// Without this the second case read as the first, and the screen told the
  /// learner that a person who had been talking the whole call "did not say
  /// anything" -- a confident, specific claim about somebody, sourced entirely
  /// from our own failure.
  final bool captureRefused;
  final bool drainComplete;

  /// Whether the writer said anything about its own capture at all.
  ///
  /// An older or foreign client omits these fields entirely. That is an absence
  /// of assertion, not an assertion of completeness, and presenting such a half
  /// as whole would put a claim in the writer's mouth it never made.
  final bool declared;

  const HalfAccounting({
    this.chunksCaptured = 0,
    this.chunksTranscribed = 0,
    this.chunksLost = 0,
    this.captureRefused = false,
    this.truncated = false,
    this.segmentsOmitted = 0,
    this.drainComplete = true,
    this.declared = false,
    this.incoherent = false,
    this.unreadableContent = false,
  });

  /// Whether this half is known NOT to be everything that was said — either
  /// because the writer says so, or because it never said otherwise.
  bool get writerAdmitsGaps =>
      !declared ||
      truncated ||
      !drainComplete ||
      segmentsOmitted > 0 ||
      chunksLost > 0 ||
      captureRefused ||
      incoherent;

  /// An accounting that cannot describe any real capture.
  ///
  /// Transcribed and lost chunks are disjoint subsets of what was captured, so
  /// `transcribed + lost <= captured` is the invariant any honest writer meets.
  /// A half that breaks it has told us something that cannot be true. Clamping
  /// such a half into shape made it read COMPLETE, which hands a nonsense event
  /// more credibility than a truthful one.
  final bool incoherent;

  /// The READER could not read one of the entries. Distinct from [truncated],
  /// which means the half did not fit: this one means part of it was corrupt.
  /// Both shorten the half, and saying "too long to send" about a malformed
  /// entry is a confident, specific, wrong diagnosis.
  ///
  /// Reader-side, so it is not serialised and takes no part in [declared] --
  /// the same footing as [incoherent].
  final bool unreadableContent;

  Map<String, dynamic> toJson() => {
    'chunks_captured': chunksCaptured,

    // Written unconditionally: our own halves always carry an assertion, so a
    // round-trip of one never reads back as undeclared.
    'chunks_transcribed': chunksTranscribed,
    'chunks_lost': chunksLost,
    'capture_refused': captureRefused,
    'truncated': truncated,
    'segments_omitted': segmentsOmitted,
    'drain_complete': drainComplete,
  };

  /// This accounting, marked as unable to describe its own content.
  HalfAccounting asIncoherent() => HalfAccounting(
    chunksCaptured: chunksCaptured,
    chunksTranscribed: chunksTranscribed,
    chunksLost: chunksLost,
    captureRefused: captureRefused,
    truncated: truncated,
    segmentsOmitted: segmentsOmitted,
    drainComplete: drainComplete,
    declared: declared,
    incoherent: true,
    unreadableContent: unreadableContent,
  );

  /// A half whose segments the READER dropped at its own ceiling. Distinct from
  /// [truncated], which is the writer's own admission: this one is our doing,
  /// and hiding it would let us present a half we shortened as whole.
  /// A half the reader shortened because part of it could not be read.
  HalfAccounting readerFoundUnreadable() => HalfAccounting(
    chunksCaptured: chunksCaptured,
    chunksTranscribed: chunksTranscribed,
    chunksLost: chunksLost,
    captureRefused: captureRefused,
    truncated: true,
    segmentsOmitted: segmentsOmitted,
    drainComplete: drainComplete,
    declared: declared,
    incoherent: incoherent,
    unreadableContent: true,
  );

  HalfAccounting readerTruncated() => HalfAccounting(
    chunksCaptured: chunksCaptured,
    chunksTranscribed: chunksTranscribed,
    chunksLost: chunksLost,
    captureRefused: captureRefused,
    truncated: true,
    segmentsOmitted: segmentsOmitted,
    drainComplete: drainComplete,
    declared: declared,
    incoherent: incoherent,
    unreadableContent: unreadableContent,
  );

  /// Tolerant by design: room content is untrusted and a partial or foreign
  /// shape must degrade to "we know less about this half", never to an
  /// exception that takes the view down.
  static HalfAccounting fromJson(Object? raw) {
    if (raw is! Map) return const HalfAccounting();
    int intOr(String key, int fallback) {
      final value = raw[key];
      return value is int && value >= 0 ? value : fallback;
    }

    // A declaration must be COMPLETE and WELL-TYPED, not merely present.
    //
    // Checking key presence alone let two things through. A content carrying
    // only some of the fields had the rest default to their optimistic values,
    // so what it omitted became assertions it never made. And a content
    // carrying every key with junk in it -- `'1'` as a string, `'yes'` for a
    // bool -- parsed to those same optimistic defaults while still counting as
    // declared, so hostile malformed content could present an empty half as
    // complete. Anything short of a full, correctly-typed accounting is
    // undeclared, which reads as incomplete.
    bool nonNegativeInt(Object? value) => value is int && value >= 0;

    // Non-negative, not merely `is int`. A count of -1 is an int, so a content
    // declaring -1 captured and -1 transcribed passed the type check, clamped
    // to zero, and assembled as a COMPLETE silent half.
    final wellFormed =
        nonNegativeInt(raw['chunks_captured']) &&
        nonNegativeInt(raw['chunks_transcribed']) &&
        raw['drain_complete'] is bool &&
        raw['truncated'] is bool &&
        nonNegativeInt(raw['segments_omitted']) &&
        nonNegativeInt(raw['chunks_lost']) &&
        raw['capture_refused'] is bool;

    final captured = intOr('chunks_captured', 0);
    final rawTranscribed = intOr('chunks_transcribed', 0);
    final rawLost = intOr('chunks_lost', 0);
    return HalfAccounting(
      declared: wellFormed,
      // Checked against the SUM, not each count alone: adding chunks_lost added
      // a second way to exceed what was captured, and a rule that names one
      // count stops holding the moment another is introduced.
      incoherent: rawTranscribed + rawLost > captured,
      chunksCaptured: captured,
      // Clamped: a half claiming more transcribed than captured is malformed,
      // and letting it through would make `writerAdmitsGaps` read false for a
      // half that is nonsense.
      chunksTranscribed: rawTranscribed.clamp(0, captured),
      chunksLost: rawLost,
      captureRefused: raw['capture_refused'] == true,
      truncated: raw['truncated'] == true,
      segmentsOmitted: intOr('segments_omitted', 0),
      // Absent means unknown, and unknown must not read as "fine".
      drainComplete: raw['drain_complete'] != false,
    );
  }
}

/// One speaker's side of a call, as the view will read it.
/// WHY a half is not a clean record of what somebody said.
///
/// The four states tell the reader what to SAY. This says what went wrong, and
/// it exists because those are different jobs. A learner reporting "it said I
/// said nothing" is unanswerable if all we kept was the state: several
/// different failures reach the same one, and without the cause we would be
/// guessing at which. Kept by default, for every half that is not clean.
enum HalfIssue {
  /// Nothing wrong. The half is everything that speaker said.
  none,

  /// This device never opened a microphone. A fact about us, not the speaker.
  microphoneRefused,

  /// Audio was captured and then lost before it could be transcribed.
  audioLost,

  /// Words were dropped to fit the event under the server's size limit.
  tooLongToSend,

  /// Part of the half could not be read. A corrupt entry, not a size problem.
  contentUnreadable,

  /// Transcription never finished; the call ended with work outstanding.
  drainAbandoned,

  /// The writer asserted nothing about its own capture, so completeness is
  /// unknown rather than confirmed. An older or foreign client.
  writerSaidNothing,

  /// The accounting contradicts itself or the content it arrived with.
  accountingImpossible,

  /// No half from this speaker at all, on a read that reached the end.
  neverWritten,

  /// We could not read the whole call -- our own ceiling, an encrypted room,
  /// or a participant list we were guessing at.
  couldNotRead,
}

/// One speaker's side of one call, as the view will read it.
class TranscriptHalf {
  final String senderId;
  final List<TranscriptSegment> segments;
  final HalfAccounting accounting;
  final HalfState state;

  const TranscriptHalf({
    required this.senderId,
    required this.segments,
    required this.accounting,
    required this.state,
  });

  /// Why this half is not a clean record, or [HalfIssue.none].
  ///
  /// Ordered by what a person reading a bug report would most want to know
  /// first: our own failures before the writer's admissions, because those are
  /// the ones we can act on. Only ever one reason is reported -- the first
  /// that applies -- since a list of every co-occurring flag is a worse
  /// starting point than the most actionable single cause.
  HalfIssue get issue {
    if (state == HalfState.absent) return HalfIssue.neverWritten;
    // FIRST among the writer's claims. An accounting that cannot be true tells
    // us nothing reliable about any of its own fields, so reporting one of
    // them as the cause would be repeating the half's own nonsense back with
    // a confident label on it.
    if (accounting.incoherent) return HalfIssue.accountingImpossible;
    if (accounting.captureRefused) return HalfIssue.microphoneRefused;
    if (accounting.unreadableContent) return HalfIssue.contentUnreadable;
    if (!accounting.declared) return HalfIssue.writerSaidNothing;
    if (accounting.chunksLost > 0) return HalfIssue.audioLost;
    if (accounting.truncated || accounting.segmentsOmitted > 0) {
      return HalfIssue.tooLongToSend;
    }
    if (!accounting.drainComplete) return HalfIssue.drainAbandoned;
    if (state == HalfState.incomplete) return HalfIssue.couldNotRead;
    return HalfIssue.none;
  }

  /// Whether this half is a person who was recorded and said nothing.
  ///
  /// Silence is NOT a fourth [HalfState]; it is [HalfState.present] with no
  /// segments, and that is deliberate -- a silent half is a complete, trusted
  /// record, and giving it its own state would put it beside "we could not
  /// find out". But the distinction is real and it is the single most
  /// dangerous one in this feature to get backwards, so it is asked here once
  /// rather than re-derived at each screen that needs it.
  bool get saidNothing => state == HalfState.present && segments.isEmpty;

  /// How much speech this half actually carries.
  ///
  /// Measured from the text present, never read off a self-declared count:
  /// choosing between duplicates by a number the content supplied would let an
  /// event claiming 999 chunks and carrying nothing beat a genuine one.
  int get contentLength => totalContentLength(segments);
}

/// A parsed `pangea.call_transcript` event, before assembly picks between
/// duplicates.
class TranscriptCandidate {
  final String senderId;
  final int originServerTs;
  final List<TranscriptSegment> segments;
  final HalfAccounting accounting;

  const TranscriptCandidate({
    required this.senderId,
    required this.originServerTs,
    required this.segments,
    required this.accounting,
  });

  /// Distinct content, so padding a half by repeating itself wins nothing:
  /// ["hello"] and ["hello", "hello"] weigh the same, and the tie-break then
  /// prefers the earlier -- which is the genuine one.
  int get contentLength => totalContentLength(segments);
}

/// The assembled transcript of one call.
class CallTranscript {
  final List<TranscriptHalf> halves;

  /// True when the reader stopped before the server said there was no more —
  /// its own page or byte ceiling. Absence cannot be concluded from a capped
  /// read, only from an exhausted one.
  final bool readerStoppedEarly;

  const CallTranscript({required this.halves, this.readerStoppedEarly = false});

  bool get isEmpty => halves.every((half) => half.segments.isEmpty);
}

/// Assembles the halves of one call.
///
/// [candidates] are every parsed transcript event found for the call, in any
/// order. [expectedSenders] is who took part, so a speaker who wrote nothing is
/// reported as absent rather than silently omitted — the difference between
/// "they said nothing" and "we never looked" is the whole point.
///
/// [exhausted] is whether retrieval reached the end of the server's relations,
/// as opposed to stopping at the reader's own cap. A capped read can never
/// conclude absence.
///
/// [participantsKnown] is whether [expectedSenders] is an ANSWER or a GUESS.
///
/// This function discards any half whose sender is not expected, and that is
/// right when the list is known: such a half is a stranger's, and giving it a
/// section in a two-person call would lend an attack the standing of a record.
/// It is a lie when the list is a guess. The caller works the participants out
/// from local state, and that can come up short -- account data that has not
/// synced, a room whose membership does not name a single other side. When it
/// does, a real participant is missing from the list, their genuine half is
/// dropped on the floor, and the reader reports the call as containing nothing
/// while claiming to have read everything.
///
/// That is the failure this whole design exists to prevent, arrived at from
/// the one direction it did not cover: not "we said they were silent when we
/// could not read them", but "we read them, could not place them, and said
/// nothing at all". Every earlier attempt to fix it improved the GUESS. The
/// assumption is what needed stating, because a better guess is still a guess
/// and the next way of getting it wrong lands here again.
///
/// So: when the list is not authoritative AND something was found that it
/// cannot place, this read cannot conclude anything. It degrades to the answer
/// it can defend -- we could not find out -- rather than presenting a partial
/// picture as the whole one.
CallTranscript assembleTranscript({
  required List<TranscriptCandidate> candidates,
  required List<String> expectedSenders,
  bool exhausted = true,
  bool participantsKnown = true,
}) {
  final bySender = <String, TranscriptCandidate>{};

  for (final candidate in candidates) {
    final held = bySender[candidate.senderId];
    if (held == null || _beats(candidate, held)) {
      bySender[candidate.senderId] = candidate;
    }
  }

  // ONLY the call's participants get a section.
  //
  // An earlier version also showed halves from senders who were not in the
  // call, reasoning that it was odd enough to surface. That was wrong: a
  // transcript event from a non-participant is a bug or an attack, and giving
  // it a section in a two-person call lends it the same standing as a real
  // half. It also let one hostile room member force unbounded sections by
  // writing under many sender ids.
  // De-duplicated: a caller passing the same participant twice would otherwise
  // get two sections for one speaker, contradicting the one-half-per-sender
  // rule this function exists to enforce.
  final senders = <String>{...expectedSenders};

  // Read but not placeable. Harmless when we know who took part -- it is
  // somebody else's event and dropping it is the point. Decisive when we do
  // not, because then it may be the very half we are about to report missing.
  final unplaceable = bySender.keys.any((id) => !senders.contains(id));

  // The single question every state below turns on: may this read draw a
  // conclusion about what a speaker did? Two independent ways for the answer
  // to be no, and both have to hold for a conclusion to be safe -- we saw
  // everything the server had, and we know whose halves we were looking for.
  final canConclude = exhausted && !(unplaceable && !participantsKnown);

  final halves = <TranscriptHalf>[];
  for (final senderId in senders) {
    final candidate = bySender[senderId];

    if (candidate == null) {
      halves.add(
        TranscriptHalf(
          senderId: senderId,
          segments: const [],
          accounting: const HalfAccounting(),
          // A read that cannot conclude cannot tell absent from unread.
          state: canConclude ? HalfState.absent : HalfState.incomplete,
        ),
      );
      continue;
    }

    halves.add(
      TranscriptHalf(
        senderId: senderId,
        segments: List.unmodifiable(candidate.segments),
        accounting: candidate.accounting,
        state: (!canConclude || candidate.accounting.writerAdmitsGaps)
            ? HalfState.incomplete
            : HalfState.present,
      ),
    );
  }

  return CallTranscript(
    halves: List.unmodifiable(halves),
    // Reported whenever a conclusion was unsafe, whichever of the two reasons
    // it was. The view says the same thing to the learner either way: some of
    // this call could not be read.
    readerStoppedEarly: !canConclude,
  );
}

/// Which of two events from the SAME sender to believe.
///
/// The one carrying more actual text, breaking ties by the earlier event.
/// Deliberately not "the earliest wins": a buggy client that emits an empty
/// half before the real one lands after the drain would otherwise hide the real
/// one for good. Content cannot be inflated without supplying the content.
bool _beats(TranscriptCandidate candidate, TranscriptCandidate held) {
  if (candidate.contentLength != held.contentLength) {
    return candidate.contentLength > held.contentLength;
  }
  return candidate.originServerTs < held.originServerTs;
}

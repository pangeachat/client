import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';

/// The weight of a half, counting each distinct utterance once.
///
/// Duplicate-selection compares this rather than raw length, so a half padded
/// by repeating its own text cannot outweigh the truthful one it copies.
int distinctContentLength(List<TranscriptSegment> segments) {
  final seen = <String>{};
  var total = 0;
  for (final segment in segments) {
    if (seen.add(segment.text)) total += segment.text.length;
  }
  return total;
}

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
    this.truncated = false,
    this.segmentsOmitted = 0,
    this.drainComplete = true,
    this.declared = false,
    this.incoherent = false,
  });

  /// Whether this half is known NOT to be everything that was said — either
  /// because the writer says so, or because it never said otherwise.
  bool get writerAdmitsGaps =>
      !declared ||
      truncated ||
      !drainComplete ||
      segmentsOmitted > 0 ||
      chunksTranscribed < chunksCaptured ||
      incoherent;

  /// An accounting that cannot describe any real capture.
  ///
  /// A writer claiming more chunks transcribed than captured, or claiming it
  /// captured nothing while shipping segments, has told us something that
  /// cannot be true. Clamping such a half into shape made it read COMPLETE,
  /// which hands a nonsense event more credibility than a truthful one.
  final bool incoherent;

  Map<String, dynamic> toJson() => {
    'chunks_captured': chunksCaptured,

    // Written unconditionally: our own halves always carry an assertion, so a
    // round-trip of one never reads back as undeclared.
    'chunks_transcribed': chunksTranscribed,
    'truncated': truncated,
    'segments_omitted': segmentsOmitted,
    'drain_complete': drainComplete,
  };

  /// This accounting, marked as unable to describe its own content.
  HalfAccounting asIncoherent() => HalfAccounting(
    chunksCaptured: chunksCaptured,
    chunksTranscribed: chunksTranscribed,
    truncated: truncated,
    segmentsOmitted: segmentsOmitted,
    drainComplete: drainComplete,
    declared: declared,
    incoherent: true,
  );

  /// A half whose segments the READER dropped at its own ceiling. Distinct from
  /// [truncated], which is the writer's own admission: this one is our doing,
  /// and hiding it would let us present a half we shortened as whole.
  HalfAccounting readerTruncated() => HalfAccounting(
    chunksCaptured: chunksCaptured,
    chunksTranscribed: chunksTranscribed,
    truncated: true,
    segmentsOmitted: segmentsOmitted,
    drainComplete: drainComplete,
    declared: declared,
    incoherent: incoherent,
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
        nonNegativeInt(raw['segments_omitted']);

    final captured = intOr('chunks_captured', 0);
    final rawTranscribed = intOr('chunks_transcribed', 0);
    return HalfAccounting(
      declared: wellFormed,
      incoherent: rawTranscribed > captured,
      chunksCaptured: captured,
      // Clamped: a half claiming more transcribed than captured is malformed,
      // and letting it through would make `writerAdmitsGaps` read false for a
      // half that is nonsense.
      chunksTranscribed: rawTranscribed.clamp(0, captured),
      truncated: raw['truncated'] == true,
      segmentsOmitted: intOr('segments_omitted', 0),
      // Absent means unknown, and unknown must not read as "fine".
      drainComplete: raw['drain_complete'] != false,
    );
  }
}

/// One speaker's side of a call, as the view will read it.
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

  /// How much speech this half actually carries.
  ///
  /// Measured from the text present, never read off a self-declared count:
  /// choosing between duplicates by a number the content supplied would let an
  /// event claiming 999 chunks and carrying nothing beat a genuine one.
  int get contentLength => distinctContentLength(segments);
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
  int get contentLength => distinctContentLength(segments);
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
CallTranscript assembleTranscript({
  required List<TranscriptCandidate> candidates,
  required List<String> expectedSenders,
  bool exhausted = true,
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
  final senders = expectedSenders;

  final halves = <TranscriptHalf>[];
  for (final senderId in senders) {
    final candidate = bySender[senderId];

    if (candidate == null) {
      halves.add(
        TranscriptHalf(
          senderId: senderId,
          segments: const [],
          accounting: const HalfAccounting(),
          // A read that stopped early cannot tell absent from unread.
          state: exhausted ? HalfState.absent : HalfState.incomplete,
        ),
      );
      continue;
    }

    halves.add(
      TranscriptHalf(
        senderId: senderId,
        segments: List.unmodifiable(candidate.segments),
        accounting: candidate.accounting,
        state: (!exhausted || candidate.accounting.writerAdmitsGaps)
            ? HalfState.incomplete
            : HalfState.present,
      ),
    );
  }

  return CallTranscript(
    halves: List.unmodifiable(halves),
    readerStoppedEarly: !exhausted,
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

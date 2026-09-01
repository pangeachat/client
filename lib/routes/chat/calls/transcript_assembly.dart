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

/// What a half SAYS, independent of how finely it was cut.
///
/// Two halves of the same speech from the same device can be split differently
/// — a newer one cut by word timings, an older one cut coarsely — and the
/// words are the same words either way. Joined on a single space so those two
/// compare equal, which is what stops the choice between them turning on an
/// artefact of the cut.
String joinedContent(List<TranscriptSegment> segments) =>
    segments.map((segment) => segment.text).join(' ');

/// Whether these segments can be laid on a shared timeline beside another
/// speaker's.
///
/// Every displayed segment must carry a position, AND both the positions and
/// the moments they are PLACED at must be non-decreasing in the order they were
/// written. Presence alone is not enough: a half with every position filled but
/// jumbled would render that speaker's own words out of order, with full
/// confidence. Monotonicity is what this writer guarantees, so a half that
/// fails it was not written by this code.
///
/// BOTH sequences are checked, because they are different sequences. A segment
/// is placed at [TranscriptSegment.orderKeyMs] — the end of its window, for one
/// that only knows which chunk it came from — and non-decreasing `atMs` does
/// not imply non-decreasing keys: a wide window followed by a narrow one
/// inverts them. Checking only `atMs` would let exactly the half this rule
/// exists to refuse render its own words backwards.
///
/// This is a check for content that is BROKEN, not for content that is
/// dishonest. A participant can fabricate positions and misorder their own
/// turns, and nothing here prevents that — they can already fabricate the
/// WORDS, which is strictly worse. Selling this as protection against a
/// malicious participant would be a promise the design cannot keep.
bool segmentsArePlaceable(List<TranscriptSegment> segments) {
  int? previousAt;
  int? previousKey;
  for (final segment in segments) {
    final at = segment.atMs;
    if (at == null) return false;
    final key = segment.orderKeyMs!;
    if (previousAt != null && at < previousAt) return false;
    if (previousKey != null && key < previousKey) return false;
    previousAt = at;
    previousKey = key;
  }
  return true;
}

/// Whether a half is empty because THIS APP threw its audio away, rather than
/// because the speaker said nothing.
///
/// [HalfAccounting.chunksSuppressed] counts chunks the writing device's own
/// speech detector examined and chose not to send. That detector's thresholds
/// are calibrated against a single recording and documented as unvalidated, so
/// a short quiet answer inside a long chunk can fail them -- and when every
/// chunk fails them, no request is ever issued and NO PROVIDER EVER READS THE
/// AUDIO. The half is then empty for a reason that is entirely ours, and
/// `present` plus no segments is [TranscriptHalf.saidNothing]: "you did not say
/// anything", sourced from our own detector, about someone who may have talked
/// the whole call.
///
/// All three terms are load-bearing, and the first is why this is NOT a term of
/// [HalfAccounting.writerAdmitsGaps]:
/// * `segments.isEmpty` -- a half that still carries words was PARTIALLY
///   suppressed, and that is ordinary. Almost every real call has a quiet
///   stretch, so flagging those would mark nearly every transcript incomplete
///   and leave the flag meaning nothing when it matters: the trap already
///   recorded on [HalfAccounting.chunksSuppressed] and [HalfAccounting.chunksLost].
/// * `chunksTranscribed == 0` -- if any chunk came back with words, a provider
///   did read this speaker, and what it did not find is not ours to explain.
/// * `chunksSuppressed > 0` -- with nothing held back there is nothing of ours
///   in the way, and an empty half is the speaker's own answer.
bool suppressionExplainsEmptiness(
  List<TranscriptSegment> segments,
  HalfAccounting accounting,
) =>
    segments.isEmpty &&
    accounting.chunksTranscribed == 0 &&
    accounting.chunksSuppressed > 0 &&
    // Suppression must account for the emptiness on its OWN, or naming it as
    // the reason buries a different one. A half with one chunk suppressed and
    // one LOST is empty for two reasons, and only the lost chunk is audio that
    // might have carried words -- saying "this app found no speech in it"
    // there reports our trim's verdict over audio the trim never judged.
    // `writerAdmitsGaps` already makes such a half incomplete on `chunksLost`,
    // so the half still reads as missing words; what this keeps out is the
    // WRONG EXPLANATION, which is the distinction this whole file is built to
    // hold. Capture refused is left to `microphoneRefused` above it for the
    // same reason.
    accounting.chunksLost == 0 &&
    // Both of these are audio our trim never judged, exactly like a lost
    // chunk, so naming the trim as the reason for the emptiness would report a
    // verdict it never gave. Dropped audio is already a gap; a discarded chunk
    // is not, and [discardExplainsEmptiness] is what keeps an empty half that
    // deferred to a sibling from reading as silence once this rule declines to
    // explain it.
    accounting.captureDroppedMs == 0 &&
    accounting.chunksDiscarded == 0;

/// Whether an empty half is empty because this device handed the stretch to a
/// sibling rather than because the speaker said nothing.
///
/// [HalfAccounting.chunksDiscarded] is deliberately not a term of
/// [HalfAccounting.writerAdmitsGaps]: a correct discard loses nothing, and a
/// half that still carries words is not incomplete for having deferred one
/// chunk. But an EMPTY half that deferred everything has produced no evidence
/// about the speaker at all, and `present` plus no segments is
/// [TranscriptHalf.saidNothing] -- "you did not say anything", said about
/// somebody whose words this device chose not to send.
///
/// The sibling's half is where those words are, and when it exists it wins the
/// duplicate contest by carrying more content. This is for when it does not:
/// the sibling crashed, or never wrote, and the only half left is the one that
/// deferred to it.
bool discardExplainsEmptiness(
  List<TranscriptSegment> segments,
  HalfAccounting accounting,
) =>
    segments.isEmpty &&
    accounting.chunksTranscribed == 0 &&
    accounting.chunksDiscarded > 0;

/// Where one device's wall clock sat relative to the SFU's, read at join.
///
/// Every position in a half is stamped from the WRITING DEVICE's own wall
/// clock, and the two halves of a call are written by two devices. Merging
/// them by comparing those absolute values is a comparison across clocks: a
/// constant skew shifts one speaker's ENTIRE half, so the transcript states
/// the wrong person spoke first and looks perfectly ordinary doing it. This
/// codebase has already lost a bug to cross-device skew -- `active_call.dart`
/// records a device two minutes fast writing one call to the room twice.
///
/// The SFU is the one clock BOTH devices observe. LiveKit stamps
/// `Participant.joinedAt` server-side at join, so it carries no send delay, no
/// queueing and no federation. The transcript event's `origin_server_ts` was
/// considered and rejected for exactly that reason: it is a RECEIVE time, so a
/// half that took five seconds to send reads as five seconds of clock skew,
/// and correcting by it would invert an ordering that was already right.
///
/// Both readings travel rather than the difference alone. The pair is what a
/// bug report can be read back from, and it costs one integer.
///
/// WHAT THE OFFSET IS ACTUALLY GOOD TO, which is NOT the resolution of either
/// reading. Both halves are read as one observation of the join response, so
/// what separates them is the SFU's own send delay plus one network leg to this
/// device — tens of milliseconds on an ordinary connection. That flight time
/// lands entirely in the offset, and it lands one way: the device reading is
/// always the later of the two. Two halves therefore disagree by roughly the
/// DIFFERENCE of their two one-way latencies to the SFU, not by their sum, and
/// not by anything either device's connect took.
///
/// Resolution sits under that error rather than over it. The SFU sends the
/// stamp twice: proto field 6, `joined_at`, in whole SECONDS, which is all
/// livekit_client's `Participant.joinedAt` exposes, and proto field 17,
/// `joined_at_ms`, the same instant in MILLISECONDS. `CallMedia` prefers the
/// fine one and falls back to the coarse one, so resolution costs nothing when
/// the SFU sent field 17 and up to a second when it did not. livekit-server has
/// only sent it since v1.8.4, and either half of a call may have been written
/// against an older one.
///
/// So: on a network worth the name the OFFSET is sub-second, a second when one
/// side ran an older SFU, and in both cases the minutes of raw clock skew are
/// gone. That is a claim about the offset, not about where a turn lands, and
/// two further things sit between the two. The offset is measured AT JOIN,
/// while a half's positions are stamped from a base the capture service reads
/// at FIRST AUDIO; both come off the same device clock, so the correction
/// carries across -- unless that clock is STEPPED in between, which nothing
/// here would notice and nothing here vouches for. And the reading is only as
/// contemporaneous as livekit_client's delivery of the join response, which is
/// immediate in the ordinary case and bounded by nothing in the pathological
/// one (see `CallMedia.anchorClocksTo`). Two turns spoken within one device's
/// latency of each other are not ordered by this and were never going to be.
///
/// AND WHERE THERE IS NO OBSERVATION THERE IS NO ANCHOR. `CallMedia` builds one
/// only from a join response it actually saw; it will not assemble a pair out
/// of whatever readings are lying around when the call ends. A pair taken at
/// two different moments is not a worse measurement of the clocks, it is a
/// measurement of something else -- of how long that device's connect took --
/// and it arrives looking exactly as confident as a real one. Absent is the
/// honest answer. What it costs is worth stating exactly, because it is NOT
/// that the transcript declines to interleave. It still interleaves:
/// [clockShiftFor] is zero for every half when the clocks cannot be reconciled,
/// so the halves are merged on RAW device wall clocks that may disagree by
/// minutes, and a reply CAN still render above the question it answers. What is
/// withheld is the TIMES -- see [turnsShareOneClock] -- so at least no reader is
/// shown a printed clock that makes a wrong order look measured. The ordering
/// risk is real and is not fixed by any of this; suppressing the times is the
/// part this layer can honestly do.
class ClockAnchor {
  /// The SFU's clock at the moment this device joined the call.
  final int sfuMs;

  /// This device's own wall clock, read at that same moment.
  final int deviceMs;

  const ClockAnchor({required this.sfuMs, required this.deviceMs});

  /// One past the largest clock reading either side will believe.
  ///
  /// 2100-01-01T00:00:00Z. Both fields are wall-clock instants, and their
  /// DIFFERENCE is what moves a speaker's turns, so a reading outside any date
  /// a clock can hold is not a measurement -- it is a number that would shift
  /// half a conversation by centuries. Room content is somebody else's word.
  static const clockCeilingMs = 4102444800000;

  /// How far this device's clock ran AHEAD of the SFU's; negative when behind.
  ///
  /// Subtracting it from a position moves that position onto the shared clock.
  int get offsetMs => deviceMs - sfuMs;

  /// The anchor for a join seen at [sfuMs] on the SFU's clock and [deviceMs] on
  /// this device's, or null when either reading is not a usable time.
  ///
  /// The same rule guards the wire and the writer, so a reading this reader
  /// would refuse is never sent in the first place.
  static ClockAnchor? of({required int sfuMs, required int deviceMs}) =>
      _usable(sfuMs) && _usable(deviceMs)
      ? ClockAnchor(sfuMs: sfuMs, deviceMs: deviceMs)
      : null;

  /// Strictly positive, not merely non-negative. Zero is the protocol default
  /// for `joinedAt`: a server that never stamped the field reads as 1970, and
  /// an offset measured against 1970 is this device's ENTIRE clock rather than
  /// its disagreement with anything.
  static bool _usable(int ms) => ms > 0 && ms < clockCeilingMs;

  /// [ms] when it states the same join [secondsMs] does, only to the
  /// millisecond, and null when it does not.
  ///
  /// The SFU sends the instant twice -- proto field 6, `joined_at`, in whole
  /// SECONDS, and field 17, `joined_at_ms` -- and this is the one rule that
  /// decides whether the second of them may be believed. A REFINEMENT ONLY:
  /// the fine field may improve a reading its coarse half already supports; it
  /// may never create one, rescue one, or name a different instant.
  ///
  /// Never over a coarse reading this class would itself refuse. Zero seconds
  /// is the unstamped protocol default, so a millisecond field arriving beside
  /// it must not turn that refusal into an answer however well-formed it looks
  /// alone.
  ///
  /// The two must agree, and the window is what makes the check possible
  /// without a second source. `joined_at` is `joined_at_ms` truncated to the
  /// second, so a server that set both puts the fine one at most 999ms past
  /// the second the coarse one names. Both arrive in the same frame, so
  /// anything outside that window is a server contradicting itself.
  ///
  /// The window is also what refuses a zero, which is the case that matters
  /// most in practice: proto3 leaves default values off the wire, so a server
  /// that never set `joined_at_ms` and one that set it to zero arrive
  /// identically, and zero sits half a century before the second reading
  /// rather than inside it. There is no "was field 17 present" flag to consult
  /// and none to invent. livekit-server has only sent the field since v1.8.4,
  /// so an older SFU is the ordinary way here rather than a corruption.
  ///
  /// TWO CALLERS, and both of them destroy something when they are wrong, so
  /// the rule is stated once. `CallMedia` anchors this device's clock on the
  /// value; `CaptureElection` orders two devices' joins by it and DISCARDS
  /// captured audio on the answer. Neither may hold its own copy of the
  /// window.
  ///
  /// The blast radius of a wrong value is bounded by the window that let it
  /// through: a reading this accepts sits inside the second the coarse reading
  /// already named.
  static int? millisecondRefinement(int secondsMs, int ms) {
    if (secondsMs <= 0) return null;
    final refines = ms - secondsMs;
    if (refines < 0 || refines >= Duration.millisecondsPerSecond) return null;
    return ms;
  }

  Map<String, dynamic> toJson() => {
    'sfu_joined_at_ms': sfuMs,
    'device_joined_at_ms': deviceMs,
  };

  /// Reads an anchor out of a transcript event's content.
  ///
  /// Tolerant, like everything else that parses room content: a non-int, a
  /// negative, an absurd or an out-of-safe-range value is ABSENT rather than
  /// thrown, and a half carrying one still shows every word it holds. An
  /// exception here would take the transcript view down over a field whose
  /// only job is to improve the ORDER of turns that are already readable.
  ///
  /// BOTH fields or neither. One alone measures nothing -- a device time with
  /// no server time beside it is just a device time -- and letting half an
  /// anchor through would put a fabricated offset of zero on a half whose
  /// clock was never compared to anything.
  static ClockAnchor? fromJson(Map<String, dynamic> content) {
    final sfu = content['sfu_joined_at_ms'];
    final device = content['device_joined_at_ms'];
    if (sfu is! int || device is! int) return null;
    return ClockAnchor.of(sfuMs: sfu, deviceMs: device);
  }

  @override
  bool operator ==(Object other) =>
      other is ClockAnchor &&
      other.sfuMs == sfuMs &&
      other.deviceMs == deviceMs;

  @override
  int get hashCode => Object.hash(sfuMs, deviceMs);

  @override
  String toString() => 'ClockAnchor(sfu $sfuMs, device $deviceMs)';
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

  /// Chunks captured and then lost, which is the only count that means a gap.
  /// Silence is captured-but-not-transcribed and is NOT a gap; see the sink.
  final int chunksLost;

  /// Chunks the WRITER'S DEVICE examined and chose not to send, having found no
  /// speech in them.
  ///
  /// A different claim from a chunk a provider read as silence, and carried
  /// separately for that reason. The provider's silence is a judgement by the
  /// thing that actually reads speech; this one is a local detector's, and a
  /// local detector can be wrong about a speaker it was never calibrated for.
  ///
  /// NOT part of [writerAdmitsGaps]. Almost every real call has a quiet
  /// stretch, so a flag raised by ordinary silence would mark nearly every
  /// transcript incomplete and leave the flag meaning nothing when it matters --
  /// the same trap already described on [chunksLost]. It is here to be READ, by
  /// anyone who wants to know how much audio a device decided against sending.
  final int chunksSuppressed;

  /// Chunks the WRITER'S DEVICE captured and deliberately did not send,
  /// because another of the same account's devices was recording the same
  /// stretch.
  ///
  /// NOT part of [writerAdmitsGaps]. A correct discard is not a gap: the words
  /// are in the sibling's half, and flagging this one incomplete would report
  /// missing speech that is present one event away.
  ///
  /// It is carried so that the claim can be QUESTIONED. The discard is the one
  /// decision in the capture path that destroys audio on the strength of a
  /// belief about a device we cannot see, and a wrong one leaves the words in
  /// neither half. Chunk indices do not line up across devices, so this is not
  /// a lookup: it is the only thing that tells a reader there is a stretch to
  /// go and find in the other half at all.
  final int chunksDiscarded;

  /// How much audio the writer's own capture path lost before it could become
  /// a chunk, in milliseconds.
  ///
  /// A gap, and a term of [writerAdmitsGaps], unlike the two counts above. It
  /// is speech that was captured and thrown away with no copy anywhere.
  ///
  /// Milliseconds rather than chunks because this audio never was one: it went
  /// inside the platform, between the microphone and the code that cuts
  /// chunks, so no chunk index describes it and no count of chunks can.
  final int captureDroppedMs;

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
    this.chunksSuppressed = 0,
    this.chunksDiscarded = 0,
    this.captureDroppedMs = 0,
    this.captureRefused = false,
    this.truncated = false,
    this.segmentsOmitted = 0,
    this.drainComplete = true,
    this.declared = false,
    this.incoherent = false,
    this.readerShortened = false,
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
      // Audio that went before it was ever a chunk. It has to be named
      // separately because every other term here counts chunks, and a stretch
      // the capture path dropped is in none of those counts -- which is
      // exactly how a half came to publish `chunksLost: 0` and read clean over
      // a hole in the recording.
      captureDroppedMs > 0 ||
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

  /// WE dropped part of this half to stay within our own ceilings.
  ///
  /// Distinct from [truncated], which is the writer saying it could not fit
  /// what it had. Both set [truncated] -- the state has to read as incomplete
  /// either way -- but only this one is ours, and reporting our ceiling as the
  /// writer omitting segments to fit sends whoever reads it to the wrong
  /// device. The second time `truncated` standing for two causes has cost a
  /// wrong diagnosis here.
  ///
  /// Reader-side, so it is not serialised and takes no part in [declared].
  final bool readerShortened;

  Map<String, dynamic> toJson() => {
    'chunks_captured': chunksCaptured,

    // Written unconditionally: our own halves always carry an assertion, so a
    // round-trip of one never reads back as undeclared.
    'chunks_transcribed': chunksTranscribed,
    'chunks_lost': chunksLost,
    'chunks_suppressed': chunksSuppressed,
    'chunks_discarded': chunksDiscarded,
    'capture_dropped_ms': captureDroppedMs,
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
    chunksSuppressed: chunksSuppressed,
    chunksDiscarded: chunksDiscarded,
    captureDroppedMs: captureDroppedMs,
    captureRefused: captureRefused,
    truncated: truncated,
    segmentsOmitted: segmentsOmitted,
    drainComplete: drainComplete,
    declared: declared,
    readerShortened: readerShortened,
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
    chunksSuppressed: chunksSuppressed,
    chunksDiscarded: chunksDiscarded,
    captureDroppedMs: captureDroppedMs,
    captureRefused: captureRefused,
    truncated: true,
    segmentsOmitted: segmentsOmitted,
    drainComplete: drainComplete,
    declared: declared,
    readerShortened: true,
    incoherent: incoherent,
    unreadableContent: true,
  );

  HalfAccounting readerTruncated() => HalfAccounting(
    chunksCaptured: chunksCaptured,
    chunksTranscribed: chunksTranscribed,
    chunksLost: chunksLost,
    chunksSuppressed: chunksSuppressed,
    chunksDiscarded: chunksDiscarded,
    captureDroppedMs: captureDroppedMs,
    captureRefused: captureRefused,
    truncated: true,
    segmentsOmitted: segmentsOmitted,
    drainComplete: drainComplete,
    declared: declared,
    readerShortened: true,
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
        raw['capture_refused'] is bool &&
        // ABSENT is fine and stays declared: every client written before this
        // count existed omits it, and treating that as "asserted nothing" would
        // retroactively strip their halves of the claim they did make.
        //
        // PRESENT and malformed is not fine, and is the same hole the rule
        // above exists to close. A count added later is not a count exempt from
        // it: `'2'` as a string or -1 would otherwise parse to the optimistic
        // zero and leave hostile content reading as a fully declared half.
        (!raw.containsKey('chunks_suppressed') ||
            nonNegativeInt(raw['chunks_suppressed'])) &&
        // Same rule again for the same reason, and stated per key rather than
        // as a loop so that adding a key without deciding this is not
        // possible: absent is a client older than the count, present and
        // malformed is content this reader must not take a declaration from.
        (!raw.containsKey('chunks_discarded') ||
            nonNegativeInt(raw['chunks_discarded'])) &&
        (!raw.containsKey('capture_dropped_ms') ||
            nonNegativeInt(raw['capture_dropped_ms']));

    final captured = intOr('chunks_captured', 0);
    final rawTranscribed = intOr('chunks_transcribed', 0);
    final rawLost = intOr('chunks_lost', 0);
    final rawSuppressed = intOr('chunks_suppressed', 0);
    final rawDiscarded = intOr('chunks_discarded', 0);
    return HalfAccounting(
      declared: wellFormed,
      // Checked against the SUM, not each count alone: adding chunks_lost added
      // a second way to exceed what was captured, and a rule that names one
      // count stops holding the moment another is introduced.
      //
      // `capture_dropped_ms` is deliberately absent from it. The four terms
      // here are chunks and the fifth is milliseconds of audio that never
      // became one, so it is not a share of the same total and adding it would
      // compare two different things.
      incoherent:
          rawTranscribed + rawLost + rawSuppressed + rawDiscarded > captured,
      chunksCaptured: captured,
      // Clamped: a half claiming more transcribed than captured is malformed,
      // and letting it through would make `writerAdmitsGaps` read false for a
      // half that is nonsense.
      chunksTranscribed: rawTranscribed.clamp(0, captured),
      chunksLost: rawLost,
      chunksSuppressed: rawSuppressed,
      chunksDiscarded: rawDiscarded,
      captureDroppedMs: intOr('capture_dropped_ms', 0),
      captureRefused: raw['capture_refused'] == true,
      truncated: raw['truncated'] == true,
      segmentsOmitted: intOr('segments_omitted', 0),
      // Absent means unknown, and unknown must not read as "fine".
      drainComplete: raw['drain_complete'] != false,
    );
  }

  /// Value equality, over every field including the reader-side ones.
  ///
  /// This is a value object and should always have had it. Without it `==` is
  /// identity, so two duplicates parsed from two events could never compare
  /// equal — and the duplicate rule in `_beats` that asks whether two halves
  /// carry the IDENTICAL accounting would have been dead code that read as
  /// protection.
  ///
  /// Every field, deliberately. Comparing on `writerAdmitsGaps` instead would
  /// collapse undeclared, truncated, an abandoned drain, lost chunks, a refused
  /// microphone and an impossible accounting into one bit — distinctions the
  /// reader shows through [HalfIssue]. Two halves that are both merely "not
  /// clean" are not interchangeable.
  @override
  bool operator ==(Object other) =>
      other is HalfAccounting &&
      other.chunksCaptured == chunksCaptured &&
      other.chunksTranscribed == chunksTranscribed &&
      other.chunksLost == chunksLost &&
      other.chunksSuppressed == chunksSuppressed &&
      other.chunksDiscarded == chunksDiscarded &&
      other.captureDroppedMs == captureDroppedMs &&
      other.captureRefused == captureRefused &&
      other.truncated == truncated &&
      other.segmentsOmitted == segmentsOmitted &&
      other.drainComplete == drainComplete &&
      other.declared == declared &&
      other.incoherent == incoherent &&
      other.readerShortened == readerShortened &&
      other.unreadableContent == unreadableContent;

  @override
  int get hashCode => Object.hash(
    chunksCaptured,
    chunksTranscribed,
    chunksLost,
    chunksSuppressed,
    chunksDiscarded,
    captureDroppedMs,
    captureRefused,
    truncated,
    segmentsOmitted,
    drainComplete,
    declared,
    incoherent,
    readerShortened,
    unreadableContent,
  );
}

/// One speaker's side of a call, as the view will read it.
/// WHY a half is not a clean record of what somebody said.
///
/// The four states tell the reader what to SAY. This says what went wrong, and
/// it exists because those are different jobs. A learner reporting "it said I
/// said nothing" is unanswerable if all we kept was the state: several
/// different failures reach the same one, and without the cause we would be
/// guessing at which. Kept by default, for every half that is not clean.
/// What the reader found when it went looking for one speaker's half.
enum HalfArrival {
  /// A half arrived and was placed.
  placed,

  /// A half was placed, AND something else from this sender was rejected --
  /// so what is shown is not known to be everything they said.
  placedWithLoss,

  /// Something from them reached us under this call's anchor and none of it
  /// became a half. Not the same as silence, and never to be shown as it.
  rejected,

  /// Nothing from them reached us at all.
  none,
}

enum HalfIssue {
  /// Nothing wrong. The half is everything that speaker said.
  none,

  /// This device never opened a microphone. A fact about us, not the speaker.
  microphoneRefused,

  /// Every chunk behind an empty half was discarded by this app's own speech
  /// detector, so nothing here was ever read by a transcriber. A fact about us
  /// too, and the reason the half must not read as silence.
  audioSuppressedLocally,

  /// Audio was captured and then lost before it could be transcribed.
  audioLost,

  /// The writer's capture path threw audio away before it could become a
  /// chunk, so a stretch of the recording is missing with no chunk to name it.
  audioDroppedAtCapture,

  /// Every chunk behind an empty half was handed to another of the same
  /// account's devices instead of being sent. A fact about which device did
  /// the recording, not about whether the speaker spoke.
  audioHeldByAnotherDevice,

  /// Words were dropped to fit the event under the server's size limit.
  tooLongToSend,

  /// WE dropped part of it at one of our own ceilings. Ours, not theirs, and
  /// the distinction is which device somebody should go and look at.
  tooLongToRead,

  /// We could not work out who was on the call, so nothing about this half is
  /// conclusive -- including, especially, its silence.
  participantsUnknown,

  /// Part of the half could not be read. A corrupt entry, not a size problem.
  contentUnreadable,

  /// Transcription never finished; the call ended with work outstanding.
  drainAbandoned,

  /// The writer asserted nothing about its own capture, so completeness is
  /// unknown rather than confirmed. An older or foreign client.
  writerSaidNothing,

  /// The accounting contradicts itself or the content it arrived with.
  accountingImpossible,

  /// At least one turn could only be bounded to the chunk of audio it came
  /// from, so it is shown at the latest moment it could have been said.
  timesApproximate,

  /// The writer never said which of its positions are exact, so none of them
  /// can be vouched for. An older or foreign client.
  timesUnstated,

  /// This account wrote halves from more than one DEVICE, and what is shown
  /// was assembled from all of them.
  ///
  /// Not a failure, and not a gap: every word both devices heard is here. What
  /// it says is that this is not one device's record, so a stretch both
  /// devices captured appears twice — see [TranscriptHalf.deviceCount] for why
  /// the reader keeps the duplicate rather than guessing which repetition was
  /// the speaker's own. It is reported so that the transcript never reads as a
  /// clean single-device record when it is not one, and so that duplicate
  /// credit is COUNTABLE: `transcript_repo` logs the count for every half,
  /// whatever [issue] ends up naming.
  assembledFromSeveralDevices,

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

  /// Whether OUR read of the room fell short -- we stopped before the server
  /// ran out -- as opposed to the writer admitting a gap in what it sent.
  ///
  /// NOT the same question as whether the transcript may be called whole. That
  /// also fails when we cannot name who was on the call, and copying THAT here
  /// made every half of such a call report "we could not read it" ahead of a
  /// microphone that never opened or audio that was lost. Not knowing who
  /// spoke is a fact about the CALL; it says nothing about our read of any
  /// particular half. Conflating a whole-transcript condition with a per-half
  /// one is the same mistake, one level up, that this field was added to fix.
  ///
  /// [HalfState.incomplete] means both, and that is right for the screen --
  /// "we cannot show you all of this" is one message either way. It is wrong
  /// for [issue], whose whole job is to name WHICH, and which is the
  /// difference between looking at this device and looking at theirs.
  final bool readWasCutShort;

  /// Whether we could not name who was on the call.
  ///
  /// The OTHER half of the question `canConclude` asks, and it has to travel
  /// here for the same reason [readWasCutShort] does. Splitting that question
  /// into its two causes fixed the diagnosis for placed halves and left this
  /// one behind: a sender we heard nothing from, on a call whose participants
  /// we could not name, has no accounting to report, so `issue` fell through
  /// to `writerSaidNothing` -- a statement about them, when the actual cause
  /// is that we do not know who "them" is.
  final bool participantsWereAGuess;

  /// What we found when we looked for this sender's half.
  ///
  /// One value, replacing the two booleans that used to say this. They could
  /// contradict each other: a sender whose only event we failed to parse got
  /// `nothingArrived: true` -- documented as "NOTHING from this sender
  /// arrived" -- beside the flag proving something had. Each review round of
  /// this class added another boolean, and the round after found the pair.
  /// An enum cannot hold two answers at once, which is the point.
  final HalfArrival arrival;

  /// Where the WRITING device's clock sat relative to the SFU's, or null when
  /// this half never said.
  ///
  /// Carried on the half and not left behind on the candidate, because the
  /// merge that needs it happens after selection: a shared timeline is built
  /// from halves, and an offset that stops at the candidate is an offset the
  /// view cannot apply. Optional because every event written before this
  /// existed, and every event from a client that does not write it, has to
  /// keep parsing -- an absent anchor costs the CORRECTION and never a word.
  final ClockAnchor? clockAnchor;

  /// Whether this half's writer marks the positions it could not pin down.
  ///
  /// It asserts exactly one thing: on a marked half, a segment carrying no
  /// span was placed at its OWN FIRST WORD. That is the claim an older or
  /// foreign writer has not made, and absence of the claim is not the claim —
  /// the same argument [HalfAccounting.declared] makes about completeness, one
  /// level down.
  ///
  /// It does NOT decide whether a span is honoured. A span can only move a turn
  /// LATER and mark it approximate, so honouring one from an unmarked writer
  /// cannot manufacture precision, and gating it would put a segment-scoped
  /// rule and a half-scoped one in contradiction over the same bytes.
  ///
  /// Carried here rather than in [HalfAccounting] on purpose. That class's `==`
  /// is deliberately every field and `_beats` reads it as "indistinguishable in
  /// every respect except whether a reader can use them"; an unmarked and a
  /// marked copy of the same speech would then compare UNEQUAL, the
  /// identical-text step would never fire, and the older unmarked copy could
  /// keep the slot. This sits beside [clockAnchor], which is the same kind of
  /// fact and already has the same kind of tie-break.
  final bool positionsMarked;

  /// How many of this sender's DEVICES wrote a half of this call.
  ///
  /// One in the ordinary case, zero when nothing was found, and more than one
  /// when two of a learner's devices were both in the call and both recorded.
  /// Halves that name no device count as one between them — see
  /// `CallTranscriptContent.deviceId` for why absence is a single key rather
  /// than a device apiece.
  ///
  /// The count of devices that WROTE, not of the halves that were assembled: a
  /// read that stopped at [kMaxDevicesPerSender] still says how many it found,
  /// and says separately, through [HalfAccounting.readerShortened], that it did
  /// not use them all.
  ///
  /// It is here because the merged half must not read as one device's clean
  /// record. Two devices' halves of one call overlap wherever both were
  /// recording, so a stretch both heard appears twice, and NOTHING here tries
  /// to tell that apart from a learner saying something twice — the words are
  /// identical in both cases and the wrong guess deletes speech somebody
  /// actually said. The duplicate is kept and declared instead of guessed at.
  final int deviceCount;

  const TranscriptHalf({
    required this.senderId,
    required this.segments,
    required this.accounting,
    required this.state,
    required this.readWasCutShort,
    required this.participantsWereAGuess,
    this.clockAnchor,
    this.positionsMarked = false,
    this.deviceCount = 1,
    required this.arrival,
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

    // NO half was placed, so every field of [accounting] is a default this
    // function constructed. Reading it as the writer's declaration reports a
    // claim nobody made -- "the writer said nothing about its own capture",
    // about a writer that sent no accounting to be silent about.
    if (arrival == HalfArrival.rejected) return HalfIssue.contentUnreadable;
    if (arrival == HalfArrival.none) {
      return readWasCutShort
          ? HalfIssue.couldNotRead
          : HalfIssue.participantsUnknown;
    }

    // OURS, all three, and they come first because the stated ordering is our
    // failures ahead of the writer's -- those are the ones we can act on.
    // Asking `state == incomplete` here instead put them last and reported
    // the writer's admission whenever both were true, because that state is
    // set by either. A cut-short read alongside lost audio was logged as the
    // writer losing audio, and nothing said we had not finished looking.
    if (accounting.unreadableContent) return HalfIssue.contentUnreadable;
    if (accounting.readerShortened) return HalfIssue.tooLongToRead;
    if (readWasCutShort) return HalfIssue.couldNotRead;

    // Then, ahead of everything DERIVED from the accounting: numbers that
    // cannot be true tell us nothing reliable about any of their own fields,
    // so reporting one of them repeats the half's own nonsense back with a
    // confident label on it. This used to sit above our failures too, which
    // was a step too far -- it is not OUR read that its numbers cast doubt on.
    if (accounting.incoherent) return HalfIssue.accountingImpossible;

    if (accounting.captureRefused) return HalfIssue.microphoneRefused;

    // Beside the microphone, and for the same reason: both are an empty half
    // that our own device produced. It sits AHEAD of every check below because
    // those are the writer's admissions and this is our doing -- the ordering
    // this getter already states. `chunksSuppressed` is only ever non-zero when
    // the wire carried a non-negative int under that name, so reading it from
    // an undeclared accounting reports a count the writer really did send.
    if (audioSuppressedLocally) return HalfIssue.audioSuppressedLocally;
    // Beside it, and for the same reason: both are an empty half our own
    // device produced, and both would otherwise fall through to a cause that
    // names the reader rather than the decision that emptied the half. The two
    // cannot both hold -- [suppressionExplainsEmptiness] declines any half
    // that also deferred a chunk -- so the order between them decides nothing;
    // what matters is that they sit above the writer's own admissions.
    if (audioHeldByAnotherDevice) return HalfIssue.audioHeldByAnotherDevice;
    if (!accounting.declared) return HalfIssue.writerSaidNothing;
    if (accounting.chunksLost > 0) return HalfIssue.audioLost;
    // Immediately after the chunks that were lost, because it is the same
    // failure one layer down: audio this device captured and could not keep.
    // Without its own name it reached the unexplained-gap branch at the bottom
    // of this ladder, which reports `couldNotRead` -- our READ, about a half we
    // read perfectly and a device that dropped the audio before we saw it.
    if (accounting.captureDroppedMs > 0) {
      return HalfIssue.audioDroppedAtCapture;
    }
    if (accounting.truncated || accounting.segmentsOmitted > 0) {
      return HalfIssue.tooLongToSend;
    }
    if (!accounting.drainComplete) return HalfIssue.drainAbandoned;

    // Last, deliberately. For a half that ARRIVED, everything above is a
    // concrete fact about it and somebody can act on those; not being able to
    // name who was on the call is true but not useful next to "the microphone
    // never opened" or "two chunks of audio were lost".
    if (participantsWereAGuess) return HalfIssue.participantsUnknown;

    // BELOW every cause above, deliberately, and it is the one placement
    // decision in this ladder that is about a SENTENCE rather than about
    // ranking. The empty-half note in `transcript_view` asks this getter for
    // the writer's own failures -- a refused microphone, lost audio, a half
    // too long to send -- so a multi-device fact reported ahead of one of those
    // would replace a specific true cause with a general one, in front of a
    // learner. It cannot be hidden by sitting here: `transcript_repo` prints
    // the count for every half, whatever this returns.
    if (deviceCount > 1) return HalfIssue.assembledFromSeveralDevices;

    // After all of those, because a half that lost audio or never opened a
    // microphone has a bigger problem than the resolution of its clock.
    //
    // NOT mutually exclusive: an unmarked writer can still send spans, so the
    // stronger statement -- we KNOW some of these are approximate -- is asked
    // first. Only one issue is ever reported, so both are invisible whenever
    // anything above applies; `transcript_repo` therefore logs the two facts
    // unconditionally rather than relying on this.
    if (approximatePositions > 0) return HalfIssue.timesApproximate;
    if (!positionsMarked && carriesPositions) return HalfIssue.timesUnstated;

    // Reached only if the half is incomplete for a reason none of the checks
    // above named. Nothing produces that today -- every route to
    // HalfState.incomplete is either a cut-short read or an admission the
    // writer made -- and it is kept so that a NEW route added later announces
    // itself as an unexplained gap rather than reading as a clean record.
    if (state == HalfState.incomplete) return HalfIssue.couldNotRead;
    return HalfIssue.none;
  }

  /// Whether this half is empty because our own speech detector discarded its
  /// audio. See [suppressionExplainsEmptiness], which is where the rule lives:
  /// asking it here rather than re-deriving it is what keeps the screen and
  /// [issue] answering the same question.
  bool get audioSuppressedLocally =>
      suppressionExplainsEmptiness(segments, accounting);

  /// Whether this half is empty because this device deferred every chunk to a
  /// sibling.
  ///
  /// Delegated to [discardExplainsEmptiness] rather than re-derived, for the
  /// reason [audioSuppressedLocally] delegates its own: assembly asks the same
  /// question when it refuses `present` for such a half, and two copies of a
  /// rule this load-bearing would eventually answer differently.
  bool get audioHeldByAnotherDevice =>
      discardExplainsEmptiness(segments, accounting);

  /// Whether this half is a person who was recorded and said nothing.
  ///
  /// Silence is NOT a fourth [HalfState]; it is [HalfState.present] with no
  /// segments, and that is deliberate -- a silent half is a complete, trusted
  /// record, and giving it its own state would put it beside "we could not
  /// find out". But the distinction is real and it is the single most
  /// dangerous one in this feature to get backwards, so it is asked here once
  /// rather than re-derived at each screen that needs it.
  ///
  /// It rests entirely on the state, which is why assembly refuses `present`
  /// for a half whose emptiness is [suppressionExplainsEmptiness]. Nothing here
  /// could tell those apart: an empty half looks the same either way, and the
  /// only thing that knows a provider never saw the audio is the accounting.
  bool get saidNothing => state == HalfState.present && segments.isEmpty;

  /// How much speech this half actually carries.
  ///
  /// Measured from the text present, never read off a self-declared count:
  /// choosing between duplicates by a number the content supplied would let an
  /// event claiming 999 chunks and carrying nothing beat a genuine one.
  int get contentLength => totalContentLength(segments);

  /// Whether this half's turns can be laid on a shared timeline.
  ///
  /// A half with nothing in it passes trivially, which is right: a speaker who
  /// said nothing has no turn that could land in the wrong place.
  bool get timelineEligible => segmentsArePlaceable(segments);

  /// How many of this half's turns know only which chunk they were said in.
  int get approximatePositions =>
      segments.where((segment) => segment.positionIsApproximate).length;

  /// Whether this half places anything at all.
  ///
  /// A half that positions nothing makes no claim about time, so neither
  /// [positionsMarked] nor its absence has anything to say about it. Asked
  /// before either is reported, on screen or in a log.
  bool get carriesPositions => segments.any((segment) => segment.atMs != null);
}

/// A parsed `pangea.call_transcript` event, before assembly picks between
/// duplicates.
class TranscriptCandidate {
  final String senderId;

  /// Which of the sender's devices wrote this event, or null when it did not
  /// say. See `CallTranscriptContent.deviceId`: absence is ONE key shared by
  /// every half that did not say, never a device of its own.
  final String? deviceId;

  final int originServerTs;
  final List<TranscriptSegment> segments;
  final HalfAccounting accounting;

  /// Where the writing device's clock sat relative to the SFU's. See
  /// [ClockAnchor]; absent on an event written before the field existed.
  final ClockAnchor? clockAnchor;

  /// Whether this event marks the positions it could not pin down. See
  /// [TranscriptHalf.positionsMarked]; false on an event written before the
  /// field existed, and on one that declared a span this reader could not use.
  final bool positionsMarked;

  const TranscriptCandidate({
    required this.senderId,
    required this.originServerTs,
    required this.segments,
    required this.accounting,
    this.deviceId,
    this.clockAnchor,
    this.positionsMarked = false,
  });

  /// Distinct content, so padding a half by repeating itself wins nothing:
  /// ["hello"] and ["hello", "hello"] weigh the same, and the tie-break then
  /// prefers the earlier -- which is the genuine one.
  int get contentLength => totalContentLength(segments);

  /// What this half says, independent of how finely it was cut.
  String get joinedText => joinedContent(segments);

  /// Whether this half could actually be rendered on a timeline.
  ///
  /// The FULL test, not merely "carries some `atMs`". A same-text half with
  /// jumbled positions that replaced a sound one would fail the render gate
  /// anyway, and the timeline would be lost to a half that could never have
  /// shown it.
  bool get timelineEligible => segmentsArePlaceable(segments);
}

/// Why a read of one call could not conclude what it contains.
///
/// Three causes, kept apart for the same reason [HalfState] keeps its three
/// states apart. They were carried as ONE boolean named for the first of them,
/// so the screen had one sentence to offer for all three and offered the
/// reader's own page ceiling every time: a room whose events we could not
/// decrypt, and a call whose participants we could not name, were both
/// explained to the reader as a call that was too long to read. A specific,
/// confident, wrong cause is worse than an unspecific true one, and the shape
/// that produces it is a boolean standing for a question with three answers.
///
/// Reported as a SET, not a winner. They are independent facts about one read
/// and any of them can hold at once; picking one to show would be the same
/// collapse a level down, and each is separately true and separately
/// actionable.
enum TranscriptReadLimit {
  /// The room encrypts its events. Nothing on the relations path decrypts, so
  /// every half comes back typed `m.room.encrypted` and is filtered out as
  /// not-a-transcript. Length had nothing to do with it.
  roomEncrypted,

  /// We could not name who was on the call, so the list of expected senders is
  /// a guess. A speaker missing from it gets no section at all -- which is the
  /// one limit that removes a whole PERSON from the screen rather than some
  /// words.
  participantsUnknown,

  /// We stopped at our own page or event ceiling, before the server said there
  /// was no more. Ours, and the only one of the three that length explains.
  readerCeiling,
}

/// The assembled transcript of one call.
class CallTranscript {
  final List<TranscriptHalf> halves;

  /// Every reason this read could not conclude what the call contains, or
  /// empty when nothing stopped it. See [TranscriptReadLimit]: absence may
  /// only be concluded from a read with no limits on it at all.
  final Set<TranscriptReadLimit> readLimits;

  const CallTranscript({
    required this.halves,
    this.readLimits = const <TranscriptReadLimit>{},
  });

  /// Whether anything at all stopped this read from concluding.
  ///
  /// The question every caller that does not care WHICH should ask. A caller
  /// that puts a sentence in front of a person does care, and reads
  /// [readLimits].
  bool get readWasInconclusive => readLimits.isNotEmpty;

  bool get isEmpty => halves.every((half) => half.segments.isEmpty);

  /// Whether this call reads as one conversation in order, rather than as two
  /// per-speaker columns.
  ///
  /// EVERY displayed half has to qualify. One half that cannot be placed makes
  /// the whole interleaving a guess, so the call falls back to the per-speaker
  /// view rather than showing part of it in order and part of it not.
  ///
  /// This is what makes a position safe to leave optional. Optionality costs
  /// the SHAPE of the screen and never the truth of the words — the opposite of
  /// `chunks_lost` or `capture_refused`, where silence would cost the truth.
  bool get timelineEligible => halves.every((half) => half.timelineEligible);

  /// Whether every half that carries words can be moved onto the SFU's clock.
  ///
  /// ALL OR NOTHING, and that is the whole rule. Correcting one half and not
  /// the other moves one speaker relative to the other by an offset measured
  /// for only one of them, and we cannot say whether that helps or harms: a
  /// correction that might invert an order which was already right is worse
  /// than leaving both halves where their devices put them.
  ///
  /// Only halves that carry WORDS are asked. A half with no segments puts
  /// nothing on the timeline, so whether its clock could be reconciled cannot
  /// move any turn -- and refusing the whole correction because a SILENT
  /// speaker's device was older would throw the fix away in calls where it
  /// works perfectly.
  bool get clocksReconcilable => halves
      .where((half) => half.segments.isNotEmpty)
      .every((half) => half.clockAnchor != null);

  /// Whether every turn the view will draw was read from ONE clock.
  ///
  /// [clocksReconcilable] answers a narrower question -- can every speaking
  /// half be MOVED onto the shared clock -- and a screen that prints times
  /// needs this one. A printed `m:ss` is a difference from the earliest turn
  /// anywhere in the transcript, and a difference is only a real elapsed time
  /// when both of its ends were read from the same clock. When two speaking
  /// halves cannot be reconciled, [clockShiftFor] returns zero for both and
  /// they are interleaved on RAW device wall clocks that may disagree by
  /// minutes -- so a reply can render above the question it answers.
  ///
  /// A transcript with at most ONE speaking half is on one clock by
  /// construction, whatever its anchor says. There is no second clock for it to
  /// disagree with, so refusing its times would hedge against a harm that
  /// cannot occur, and would silence every call where only one person spoke.
  ///
  /// This does NOT claim the times are RIGHT. A single device's clock can be
  /// wrong about the hour; what it cannot be is wrong relative to itself, and
  /// every time on screen is a difference between two of its own readings.
  bool get turnsShareOneClock =>
      clocksReconcilable ||
      halves.where((half) => half.segments.isNotEmpty).length <= 1;

  /// How far to move one half's positions to put it on the shared clock.
  ///
  /// Zero unless [clocksReconcilable], which is what makes an old event, a
  /// foreign client, or a half whose anchor would not parse cost the
  /// CORRECTION and nothing else: the call still renders exactly as it did
  /// before this field existed.
  ///
  /// One constant per half, subtracted from every position in it. That is what
  /// keeps `segmentsArePlaceable` true after the shift -- a single constant
  /// cannot reorder a sequence, so a half the render gate already accepted
  /// stays non-decreasing, and the gate may go on reading the raw positions.
  int clockShiftFor(TranscriptHalf half) =>
      clocksReconcilable ? (half.clockAnchor?.offsetMs ?? 0) : 0;
}

/// How many of one sender's devices a single half may be assembled from.
///
/// A ceiling on untrusted content, not a statement about how many devices a
/// learner may own. Every half is bounded by
/// `CallTranscriptContent.maxSegments` and `maxTotalChars` as it is parsed, and
/// keying by sender alone kept exactly one of them — so one hostile room member
/// could not make the screen draw more than one half's worth of widgets however
/// many events they wrote. Keying by DEVICE removes that bound: a peer writing
/// two hundred events under two hundred invented device ids would otherwise
/// assemble into one half two hundred times the size, and the transcript dialog
/// builds every segment eagerly.
///
/// Four, because the case this feature exists for is two, three is a learner
/// with a tablet, and beyond that the read is a ceiling rather than a call. What
/// happens past it is stated rather than silent: the halves carrying the most
/// speech are assembled, [HalfAccounting.readerShortened] says the reader
/// dropped something, and [TranscriptHalf.deviceCount] still reports how many
/// devices were FOUND.
const kMaxDevicesPerSender = 4;

/// One sender's halves, once every device that wrote one has been taken into
/// account. The shape [assembleTranscript] needs to build a [TranscriptHalf].
class _AssembledHalf {
  final List<TranscriptSegment> segments;
  final HalfAccounting accounting;
  final ClockAnchor? clockAnchor;
  final bool positionsMarked;

  /// How many devices WROTE, including any the ceiling above turned away.
  final int deviceCount;

  const _AssembledHalf({
    required this.segments,
    required this.accounting,
    required this.clockAnchor,
    required this.positionsMarked,
    required this.deviceCount,
  });
}

/// Adds two counts without letting the total wrap.
///
/// Counts come off untrusted content, where `chunks_lost` may be any
/// non-negative int the JSON could hold. Two of those summed can pass 2^63 and
/// come back NEGATIVE, and a negative count reads as zero to every rule that
/// asks whether a half admits a gap — so a half that lost audio would assemble
/// as a clean record. Saturating is a wrong number; wrapping is a wrong answer.
int _saturatingSum(int a, int b) {
  const ceiling = 0x7FFFFFFFFFFFFFFF;
  return a > ceiling - b ? ceiling : a + b;
}

/// What several devices' accountings add up to for one speaker.
///
/// Each field composes the way a claim about SEVERAL devices composes, which is
/// not always the way the same field composes for one:
///
/// * The counts are summed. They describe chunks each device cut from its own
///   recording, so the total describes what this account's devices captured
///   between them — and it DOUBLE-COUNTS whatever both were recording at once,
///   exactly as the merged segments do. That is the duplication this merge
///   preserves rather than guesses at, and the accounting says the same thing
///   the words do.
/// * [HalfAccounting.declared] is AND. A merged half may only carry the claim
///   EVERY contributor made; inheriting one writer's declaration would put a
///   claim in another writer's mouth it never made.
/// * [HalfAccounting.drainComplete] is AND for the same reason, from the other
///   direction: one device that never finished transcribing leaves the merged
///   record short whatever the other managed.
/// * [HalfAccounting.captureRefused] is AND, and it is the one field where OR
///   would be a confident, specific, wrong answer. It exists to say an empty
///   half is a fact about US rather than about the speaker. If one device's
///   microphone never opened and the other's recorded the call, the ACCOUNT's
///   half is not that fact, and reporting it would blame a microphone for a
///   half that is full of words. What that device did not capture is already in
///   the counts it contributed, which are zero.
/// * Everything that means "not whole" — truncated, incoherent, reader-side
///   shortening, unreadable content — is OR. One contributor's gap is the
///   merged half's gap.
HalfAccounting _mergeAccounting(
  List<HalfAccounting> parts, {
  required bool readerDroppedADevice,
}) {
  var captured = 0;
  var transcribed = 0;
  var lost = 0;
  var suppressed = 0;
  var discarded = 0;
  var droppedMs = 0;
  var omitted = 0;
  var refused = true;
  var drained = true;
  var declared = true;
  var truncated = readerDroppedADevice;
  var incoherent = false;
  var readerShortened = readerDroppedADevice;
  var unreadable = false;

  for (final part in parts) {
    captured = _saturatingSum(captured, part.chunksCaptured);
    transcribed = _saturatingSum(transcribed, part.chunksTranscribed);
    lost = _saturatingSum(lost, part.chunksLost);
    suppressed = _saturatingSum(suppressed, part.chunksSuppressed);
    discarded = _saturatingSum(discarded, part.chunksDiscarded);
    droppedMs = _saturatingSum(droppedMs, part.captureDroppedMs);
    omitted = _saturatingSum(omitted, part.segmentsOmitted);
    refused = refused && part.captureRefused;
    drained = drained && part.drainComplete;
    declared = declared && part.declared;
    truncated = truncated || part.truncated;
    incoherent = incoherent || part.incoherent;
    readerShortened = readerShortened || part.readerShortened;
    unreadable = unreadable || part.unreadableContent;
  }

  return HalfAccounting(
    chunksCaptured: captured,
    chunksTranscribed: transcribed,
    chunksLost: lost,
    chunksSuppressed: suppressed,
    chunksDiscarded: discarded,
    captureDroppedMs: droppedMs,
    captureRefused: refused,
    truncated: truncated,
    segmentsOmitted: omitted,
    drainComplete: drained,
    declared: declared,
    incoherent: incoherent,
    readerShortened: readerShortened,
    unreadableContent: unreadable,
  );
}

/// [segment] moved from one device's wall clock onto another's, or null when
/// the result is not a time this reader would have accepted in the first place.
///
/// Both anchors are readings of the SAME join against the SFU's clock, so the
/// difference of their offsets is the constant that separates the two devices'
/// stamps. [TranscriptSegment.spanMs] is a delta and is invariant under it,
/// which is why only the position moves.
///
/// Null on any position the shift pushes out of range. The anchors come off
/// room content and are bounded but not benign: one at either end of
/// [ClockAnchor.clockCeilingMs] can move a position before the epoch or past
/// what survives a JSON round trip, and a merge that quietly adopted such a
/// number would order two speakers by it.
TranscriptSegment? _shifted(TranscriptSegment segment, int deltaMs) {
  if (deltaMs == 0) return segment;
  final at = segment.atMs;
  if (at == null) return null;
  final moved = at + deltaMs;
  if (moved < 0 || moved >= TranscriptSegment.atMsCeiling) return null;
  if (moved + (segment.spanMs ?? 0) >= TranscriptSegment.atMsCeiling) {
    return null;
  }
  return TranscriptSegment(segment.text, atMs: moved, spanMs: segment.spanMs);
}

/// Which of one sender's device halves to keep when there are more of them than
/// [kMaxDevicesPerSender]: the ones carrying the most speech.
///
/// The DEVICE breaks the tie, rather than the order the list happened to arrive
/// in. `List.sort` is not documented as stable, so two halves of equal length
/// would otherwise be chosen between differently on two reads of the same call
/// -- and which half of a learner's speech is shown is not a thing to leave to
/// a sort implementation.
int _byMostSpeech(TranscriptCandidate a, TranscriptCandidate b) {
  final byContent = b.contentLength.compareTo(a.contentLength);
  return byContent != 0
      ? byContent
      : (a.deviceId ?? '').compareTo(b.deviceId ?? '');
}

/// Every device's half of one speaker, combined into the one half the view
/// reads.
///
/// [perDevice] is the winning candidate from each of that sender's devices, in
/// device order, and it is never empty.
///
/// ONE DEVICE IS THE ORDINARY CASE and it is returned untouched: same segments,
/// same anchor, same claim about its positions. Everything below runs only when
/// a learner had two devices in one call, which is what this whole change
/// exists for.
///
/// HOW THE MERGE ORDERS. Each half's positions are stamped from its own
/// device's wall clock and those clocks disagree — this codebase has already
/// lost a bug to it. The correction that already exists is the one used here:
/// every half carries the anchor it read against the SFU at join, so the
/// difference of two anchors' offsets is the constant that puts one device's
/// stamps on the other's clock. The merged half keeps the FIRST speaking
/// device's anchor and every other device's positions are moved onto that
/// device's clock, which leaves the half exactly what the rest of this file
/// expects: one anchor describing every position in it, and one constant
/// ([CallTranscript.clockShiftFor]) still enough to put the whole half on the
/// SFU's clock beside the other speaker's. No second ordering scheme, and the
/// event timestamps are not consulted — a send that took five seconds would
/// read as five seconds of skew.
///
/// WHERE IT CANNOT ORDER, IT SAYS SO INSTEAD OF GUESSING. Two speaking devices
/// can only be interleaved when both anchored their clocks and every segment
/// carries a position. Failing that, the halves are laid end to end in device
/// order — every word kept, none reordered within its own device — and the
/// merged half carries NO anchor and does not mark its positions. Both of those
/// are read downstream: an unanchored speaking half makes
/// [CallTranscript.clocksReconcilable] false for the whole call, and unmarked
/// positions make every turn [TurnTime.unstated], so no printed time rests on a
/// sequence this reader could not order. The concatenation will usually fail
/// [segmentsArePlaceable] as well, which drops the call to the per-speaker
/// view — the shape that claims nothing about ordering, which is the right
/// shape for a merge that could not establish one.
///
/// A merge that DID order can land there too, and it is worth saying so rather
/// than being surprised by it. The sort is by [TranscriptSegment.orderKeyMs],
/// which is what the view places a turn at, so the keys come out
/// non-decreasing; the `atMs` sequence beside them need not, because one
/// device's approximate turn can carry an earlier position and a later key than
/// the other's exact one. [segmentsArePlaceable] asks for both, so such a call
/// renders per speaker. Every word is still shown, in the order the merge
/// established — what is lost is the interleaved SHAPE, which is the same cost
/// this file already accepts for a half that carries an unplaced segment.
///
/// WHAT IT DOES NOT DO IS DE-DUPLICATE. Two devices recording one person
/// capture the same speech wherever they were both recording, so the merged
/// half repeats it. Nothing here tries to collapse that, and the reason is
/// recorded one function up at [totalContentLength]: repeated text is also what
/// a learner saying something twice looks like, the two are indistinguishable
/// in the words, and the wrong guess deletes speech somebody actually said.
/// A visible duplicate is a duplicate somebody can count;
/// [TranscriptHalf.deviceCount] is what says it is there.
_AssembledHalf _assembleDevices(List<TranscriptCandidate> perDevice) {
  final found = perDevice.length;

  // Past the ceiling, the halves carrying the most speech are the ones kept.
  // See [_byMostSpeech] for what settles a tie, and why it cannot be left to
  // the sort.
  final kept = found <= kMaxDevicesPerSender
      ? perDevice
      : ([
          ...perDevice,
        ]..sort(_byMostSpeech)).take(kMaxDevicesPerSender).toList();
  final droppedADevice = kept.length < found;
  if (droppedADevice) {
    // Back into device order: the selection above is by content, and the ORDER
    // of a concatenation must not depend on how much each device happened to
    // say.
    kept.sort((a, b) => (a.deviceId ?? '').compareTo(b.deviceId ?? ''));
  }

  final accounting = _mergeAccounting([
    for (final candidate in kept) candidate.accounting,
  ], readerDroppedADevice: droppedADevice);

  // The ones that put anything on the timeline. A device that wrote an empty
  // half orders nothing, so neither its anchor nor its silence about one may
  // decide whether the speaking halves can be interleaved -- the same carve-out
  // [CallTranscript.clocksReconcilable] already makes one level up.
  final speaking = [
    for (final candidate in kept)
      if (candidate.segments.isNotEmpty) candidate,
  ];

  if (speaking.length <= 1) {
    // Nothing to order against, so nothing is moved and nothing is withheld:
    // whatever the one speaking device asserted is what the half asserts. This
    // is the shape a merge takes in the case the rest of the design aims for,
    // where the device that does not carry on writes an empty half or none.
    final only = speaking.firstOrNull;
    return _AssembledHalf(
      segments: only?.segments ?? const [],
      accounting: accounting,
      clockAnchor:
          only?.clockAnchor ??
          // An empty half places nothing, so this anchor can never move a turn
          // -- `clocksReconcilable` asks only halves that carry words. It is
          // carried rather than dropped so a half that said what its clock read
          // is not made to look like one that never said.
          kept.map((candidate) => candidate.clockAnchor).nonNulls.firstOrNull,
      positionsMarked: only?.positionsMarked ?? false,
      deviceCount: found,
    );
  }

  // The clock every position in the merged half will be expressed on. The
  // first speaking device's, taken in device order, so it does not depend on
  // how much either device happened to say.
  final reference = speaking.first.clockAnchor;
  final ordered = <({int group, int index, TranscriptSegment segment})>[];
  var orderable = reference != null;

  if (reference != null) {
    for (var group = 0; group < speaking.length && orderable; group++) {
      final candidate = speaking[group];
      final anchor = candidate.clockAnchor;
      if (anchor == null) {
        // One device that never compared its clock to the SFU's is enough.
        // Ordering the others around it would place its turns by an offset
        // measured for somebody else.
        orderable = false;
        break;
      }
      final delta = reference.offsetMs - anchor.offsetMs;
      for (var index = 0; index < candidate.segments.length; index++) {
        final moved = _shifted(candidate.segments[index], delta);
        if (moved == null || moved.atMs == null) {
          // One unplaced segment anywhere is enough: it cannot be ordered
          // against the other device's, and interleaving the rest around it
          // would put a real turn in a position nothing supports.
          orderable = false;
          break;
        }
        ordered.add((group: group, index: index, segment: moved));
      }
    }
  }

  if (!orderable) {
    return _AssembledHalf(
      segments: [for (final candidate in kept) ...candidate.segments],
      accounting: accounting,
      // Null and false, and both are load-bearing. The positions in this list
      // come from two clocks that were never compared, so no anchor describes
      // them and no claim about their exactness survives the mixing. Together
      // they stop any time being printed over an order this reader could not
      // establish -- including in a call where this is the only speaking half,
      // which [CallTranscript.turnsShareOneClock] would otherwise call one
      // clock on the strength of there being no second speaker.
      clockAnchor: null,
      positionsMarked: false,
      deviceCount: found,
    );
  }

  // By the moment each turn is PLACED at -- the latest it could have been said
  // -- which is the same key the view orders by, so the merged half reads in
  // the order it will be drawn in. The group and the index behind it make the
  // comparison a strict total order: two devices can legitimately stamp the
  // same instant, and `List.sort` is not stable.
  ordered.sort((a, b) {
    final byKey = a.segment.orderKeyMs!.compareTo(b.segment.orderKeyMs!);
    if (byKey != 0) return byKey;
    final byGroup = a.group.compareTo(b.group);
    return byGroup != 0 ? byGroup : a.index.compareTo(b.index);
  });

  return _AssembledHalf(
    segments: [for (final entry in ordered) entry.segment],
    accounting: accounting,
    clockAnchor: reference,
    // Every speaking contributor, on the same terms as [HalfAccounting.declared]
    // and for the same reason: the claim is about the segments being shown, and
    // one writer that never made it leaves segments here nobody vouched for.
    positionsMarked: speaking.every((candidate) => candidate.positionsMarked),
    deviceCount: found,
  );
}

/// Assembles the halves of one call.
///
/// [candidates] are every parsed transcript event found for the call, in any
/// order. [expectedSenders] is who took part, so a speaker who wrote nothing is
/// reported as absent rather than silently omitted — the difference between
/// "they said nothing" and "we never looked" is the whole point.
///
/// ONE HALF PER SENDER still, and no longer one EVENT per sender. A learner
/// with two devices in one call writes two events, and both are that person's
/// speech: they are grouped by device, chosen between within a device, and
/// combined across devices into the one half a speaker gets. See
/// [_assembleDevices] for how that combination orders, what it refuses to
/// order, and why it keeps a duplicate rather than guess which repetition was
/// real.
///
/// [exhausted] is whether retrieval reached the end of the server's relations,
/// as opposed to stopping at the reader's own cap. A capped read can never
/// conclude absence.
///
/// [participantsKnown] is whether [expectedSenders] is an ANSWER or a GUESS.
///
/// [encrypted] is whether the room encrypts its events, which is a THIRD way
/// for this read to be inconclusive and arrives here as its own fact rather
/// than folded into [exhausted]. Folding it in was how the screen came to
/// explain an undecryptable room as a call that was too long to read: the two
/// were indistinguishable by the time anything could say so. See
/// [TranscriptReadLimit].
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
  bool encrypted = false,

  /// Senders whose event the reader found and could not parse.
  ///
  /// Separate from [candidates] precisely because there is nothing to place: a
  /// content that will not parse still carries a SENDER, and that is the whole
  /// difference between "they wrote nothing" and "they wrote something we
  /// could not read".
  Set<String> unreadableSenders = const {},
}) {
  // BY SENDER AND BY DEVICE, because a sender is not a recorder.
  //
  // Keyed by sender alone, two of one learner's devices in one call wrote two
  // halves that were indistinguishable here: the second was discarded and the
  // first was presented, with its own accounting, as the whole of what that
  // person said. That is the loss this grouping exists to stop, and it is worse
  // than a refused send because nothing about it is visible.
  //
  // The inner key is the device or the empty string, and the empty string is
  // ONE key shared by every half that did not name a device -- events written
  // before the field existed, foreign clients, and a client that cannot name
  // its own device. See `CallTranscriptContent.deviceId`. That is what keeps
  // the rooms that already exist reading exactly as they did: two halves from
  // two old builds still key alike, so one is still kept, and this change
  // reaches them only once one of the two devices is updated.
  final bySender = <String, Map<String, TranscriptCandidate>>{};

  for (final candidate in candidates) {
    final byDevice = bySender.putIfAbsent(candidate.senderId, () => {});
    final key = candidate.deviceId ?? '';
    final held = byDevice[key];
    // Still one half per DEVICE, chosen exactly as before. A resend, or a buggy
    // writer's empty half landing before the real one, is a duplicate from one
    // recorder and the choice between them is unchanged; what is no longer
    // treated as a duplicate is a second DEVICE's half of the same call.
    if (held == null || _beats(candidate, held)) {
      byDevice[key] = candidate;
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

  // Every reason this read may not draw a conclusion about what a speaker did.
  //
  // Collected rather than counted, because a caller has to be able to SAY
  // which. Three independent ways for the answer to be no -- we saw everything
  // the server had, we could read what it gave us, and we know whose halves we
  // were looking for -- and each is a different sentence to a person reading
  // the call.
  //
  // The participants one used to be narrower than that sentence: it asked
  // whether an UNPLACEABLE half had turned up while the participants were
  // unknown. That catches the peer who wrote something, because their half
  // cannot be placed -- and misses the peer who wrote NOTHING entirely. With
  // nobody identifiable there is then no unplaceable half, no second sender to
  // report absent, and the screen shows one side of a conversation and says
  // nothing is missing. Not knowing who was on a call is by itself a reason not
  // to declare its record whole.
  final readLimits = <TranscriptReadLimit>{
    if (encrypted) TranscriptReadLimit.roomEncrypted,
    if (!participantsKnown) TranscriptReadLimit.participantsUnknown,
    if (!exhausted) TranscriptReadLimit.readerCeiling,
  };

  // The single question every state below turns on: may this read draw a
  // conclusion about what a speaker did? Only a read with nothing at all
  // standing in its way.
  final canConclude = readLimits.isEmpty;

  // OUR failure to read this half's content, which for the per-half diagnosis
  // is what an encrypted room is: the events came back sealed, so the reader
  // saw none of them, whatever the server said about paging. It has to be
  // asked as a fact about the CONTENT rather than about the paging, or an
  // encrypted room whose relations list is simply empty reports its halves as
  // `participantsUnknown` -- a confident, specific, wrong cause, and the one
  // this change exists to stop.
  //
  // Not the same question as [canConclude]: an unnamed participant list is a
  // fact about the CALL and says nothing about our read of any particular
  // half. See [TranscriptHalf.readWasCutShort].
  final readWasCutShort = !exhausted || encrypted;

  final halves = <TranscriptHalf>[];
  for (final senderId in senders) {
    final byDevice = bySender[senderId];

    // In device order, so a call assembles the same way every time it is read.
    // The empty key sorts first, which is only a convention -- what matters is
    // that it is FIXED, because it decides the order of a concatenation this
    // reader could not put on one clock.
    final perDevice = byDevice == null
        ? const <TranscriptCandidate>[]
        : (byDevice.keys.toList()..sort())
              .map((key) => byDevice[key]!)
              .toList();
    final candidate = perDevice.isEmpty ? null : _assembleDevices(perDevice);

    // Something arrived from them that we could not read. It is not absence,
    // whatever else the read managed, and it is not the writer's fault.
    final wasUnreadable = unreadableSenders.contains(senderId);

    if (candidate == null) {
      halves.add(
        TranscriptHalf(
          senderId: senderId,
          segments: const [],
          // Empty, and carrying no claim at all. Setting `unreadableContent`
          // here made this synthesised accounting assert something, which is
          // the exact habit that produced "the writer said nothing about its
          // own capture" out of a placeholder. What arrived is [arrival]'s
          // job, and nothing about a half nobody sent belongs in a shape
          // built to describe one that was.
          accounting: const HalfAccounting(),
          // A read that cannot conclude cannot tell absent from unread -- and
          // neither can one that held their event and could not parse it.
          state: (canConclude && !wasUnreadable)
              ? HalfState.absent
              : HalfState.incomplete,
          readWasCutShort: readWasCutShort,
          participantsWereAGuess: !participantsKnown,
          arrival: wasUnreadable ? HalfArrival.rejected : HalfArrival.none,
          // No anchor, for the same reason there is no accounting: nobody
          // wrote one. A synthesised offset of zero would be this reader
          // asserting the two clocks agreed, about a device that never told us
          // what its clock said.
          //
          // No device wrote either, which is a different statement from the
          // one device the default would make.
          deviceCount: 0,
        ),
      );
      continue;
    }

    halves.add(
      TranscriptHalf(
        senderId: senderId,
        segments: List.unmodifiable(candidate.segments),
        // A half we DID place, from a sender who also sent something we
        // could not read. The unreadable one may have been the fuller copy,
        // so what is shown is not known to be everything they said.
        accounting: wasUnreadable
            ? candidate.accounting.readerFoundUnreadable()
            : candidate.accounting,
        state:
            (!canConclude ||
                wasUnreadable ||
                candidate.accounting.writerAdmitsGaps ||
                // Not folded into `writerAdmitsGaps`, which is about the
                // ACCOUNTING alone and would then have to raise the flag on
                // every partially suppressed half -- nearly all of them. This
                // one needs the segments as well, and only the all-suppressed
                // half it names is unsupported as `present`.
                suppressionExplainsEmptiness(
                  candidate.segments,
                  candidate.accounting,
                ) ||
                // Here rather than in `writerAdmitsGaps` for the same reason,
                // and a different one besides: a discard is not a gap, so a
                // half that still carries words must not read as incomplete
                // for having deferred one chunk. Only the EMPTY half this
                // names is unsupported as `present`, because `present` plus no
                // segments is read as the speaker having said nothing.
                discardExplainsEmptiness(
                  candidate.segments,
                  candidate.accounting,
                ))
            ? HalfState.incomplete
            : HalfState.present,
        readWasCutShort: readWasCutShort,
        participantsWereAGuess: !participantsKnown,
        arrival: wasUnreadable
            ? HalfArrival.placedWithLoss
            : HalfArrival.placed,
        // From what was actually assembled, never from any copy that lost: the
        // offset has to describe the positions being shown, and two copies from
        // one device can carry different anchors if it rejoined. Across DEVICES
        // it is the anchor every position in this half has been moved onto, or
        // null when they could not be -- see [_assembleDevices].
        clockAnchor: candidate.clockAnchor,
        // Same rule, same reason: the claim has to describe the segments being
        // shown, and only the copies that supplied them may make it.
        positionsMarked: candidate.positionsMarked,
        deviceCount: candidate.deviceCount,
      ),
    );
  }

  return CallTranscript(
    halves: List.unmodifiable(halves),
    // Every reason, carried through. This used to be one boolean set from
    // `!canConclude`, which is all the view needed to know THAT a conclusion
    // was unsafe and nothing it needed to say WHY -- so it said the only thing
    // the boolean's name suggested, and told a reader whose room we could not
    // decrypt that the call had been too long.
    readLimits: Set.unmodifiable(readLimits),
  );
}

/// Which of two events from the SAME sender AND THE SAME DEVICE to believe.
///
/// The device half of that is not decoration. This rule reads two events as
/// copies of one recording and keeps one, which is right for a resend or for a
/// buggy writer's empty first attempt, and wrong for the other half of a
/// conversation: a second DEVICE's event is not a copy, and discarding it
/// destroyed speech while the survivor claimed to be whole. Two events reach
/// this function only after `assembleTranscript` has grouped them by device.
///
/// The one carrying more actual text, breaking ties by the earlier event.
/// Deliberately not "the earliest wins": a buggy client that emits an empty
/// half before the real one lands after the drain would otherwise hide the real
/// one for good. Content cannot be inflated without supplying the content.
///
/// Ahead of both of those sits one narrow step, for two halves that are the
/// SAME SPEECH and differ only in how much of it a reader can use.
bool _beats(TranscriptCandidate candidate, TranscriptCandidate held) {
  // ABOVE the length test, not between it and the tie-break. `contentLength`
  // sums segment texts and counts no separators, so ["hello world"] measures 11
  // and ["hello", "world"] measures 10. Those are the SAME WORDS, and they are
  // exactly the pair this step exists for: a newer half split finely by timings
  // against an older one that was not. Placed below the length test, the old
  // half wins on a difference that is an artefact of how it was cut, and the
  // step never fires in the case it was written for.
  //
  // Identical text, never equal length. Equal length means two halves that
  // happen to be the same size, which is not the same words, and letting a
  // positioned one win there would change what the transcript SAYS rather than
  // only its order.
  //
  // Identical accounting too, so this does nothing except choose between halves
  // that are indistinguishable in every respect this feature cares about EXCEPT
  // whether they can be placed in time — the same sender's old untimed copy
  // against their new timed one, which is the only case it was ever for.
  //
  // The trade is narrow and worth naming: a later duplicate carrying positions
  // displaces an earlier one without them, from the same sender's own device,
  // with every word the same. Without the step, an old untimed copy keeps the
  // slot and the timeline never renders.
  if (candidate.joinedText == held.joinedText &&
      candidate.accounting == held.accounting) {
    // What is left to choose on is how much of this speech a reader can USE,
    // and there are two such properties. They are asked in the order they
    // matter: a half that cannot be placed at all shows no timeline, while one
    // that cannot be corrected shows the timeline its device asserted.
    if (candidate.timelineEligible != held.timelineEligible) {
      return candidate.timelineEligible;
    }
    // A clock anchor, on the same terms and for the same reason. Left out at
    // first on the argument that an unanchored copy winning costs only the
    // correction -- true, and beside the point: the anchor WAS written, and
    // letting an older copy of the identical speech bury it reinstates the
    // skew this whole change exists to remove, silently. The words cannot
    // differ here, so nothing about what the transcript SAYS turns on this.
    final anchored = candidate.clockAnchor != null;
    if (anchored != (held.clockAnchor != null)) return anchored;

    // And last of the three, which is a decision and not an accident.
    //
    // An anchor and a position marker can disagree, and one of them has to
    // yield. The tie-break is SCOPE, not size: `clocksReconcilable` is ALL OR
    // NOTHING across the call, so preferring the unanchored copy here would
    // cost EVERY half its clock correction -- including the other speaker's,
    // which has nothing to do with this dispute -- to buy this one half its
    // disclosure. The call-wide loss loses.
    //
    // The cost of that is real and is not being minimised. The two copies
    // agree on their WORDS and their accounting, which is all `joinedText` and
    // `==` compare, so the unmarked copy may well be carrying no spans at all:
    // choosing it can leave this half's turns both undisclosed and placed at
    // an estimate. How wrong that estimate is cannot be bounded from here --
    // an unmarked half by definition tells us nothing about its own precision
    // -- and saying otherwise would be a made-up number. What can be said is
    // that the half reads as `timesUnstated` and the screen tells the reader
    // its ordering may be wrong.
    final marked = candidate.positionsMarked;
    if (marked != held.positionsMarked) return marked;
  }
  if (candidate.contentLength != held.contentLength) {
    return candidate.contentLength > held.contentLength;
  }
  return candidate.originServerTs < held.originServerTs;
}

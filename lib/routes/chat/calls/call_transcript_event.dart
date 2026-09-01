import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';

/// The `pangea.call_transcript` event: one recording of one side of one call.
///
/// One event per DEVICE, never split into parts. It was one event per SPEAKER
/// until two of a learner's devices turned out to be able to record one call
/// between them, which is two recordings of one side and not two parts of one
/// recording: a device id is not a sequence number, and a device still writes
/// once. See [deviceId], and `assembleTranscript` for how the halves are read
/// back as one side of the conversation.
///
/// Parts were the first design and every review found another corner in them —
/// a sequence counter that has to survive process death across a rejoin, a
/// declared part count a reader must not trust, non-contiguous numbering from a
/// buggy writer, and no clean answer for what "absent" means while parts are
/// still arriving. A device's half is one event or it is missing, and both are
/// decidable at a glance.
///
/// Anchored by relation to `call_key` — the caller's membership event, which
/// BOTH sides know as soon as the call starts. The call card is written by only
/// one side and is not written at all when both sides reload out, so anchoring
/// to it would strand the other half in exactly the case a transcript is most
/// wanted.
class CallTranscriptContent {
  /// The caller's membership event id: the anchor both sides share.
  final String callKey;

  /// What was said, in the order it was said.
  final List<TranscriptSegment> segments;

  /// What the writing device claims about its own capture. A description, not
  /// a proof — see [TranscriptHalf.contentLength] for why duplicates are
  /// chosen by content rather than by these numbers.
  final HalfAccounting accounting;

  /// The language this half was transcribed in, when the provider reported one.
  final String? langCode;

  /// Which of the sender's DEVICES wrote this half.
  ///
  /// OPTIONAL on the wire, in both directions, and the whole reason the field
  /// exists is that two devices of one account can both be in one call and both
  /// record. Keyed by sender alone, their halves are indistinguishable: the
  /// reader groups by sender, keeps one, and presents it as the whole of what
  /// that person said. See `assembleTranscript`.
  ///
  /// ABSENT MEANS "THIS WRITER DID NOT SAY", and never "this is a different
  /// device from the last one". Every half written before this field existed
  /// carries nothing, so does any foreign client's, and so does one of ours on
  /// a client that cannot name its own device. All of those key alike, which
  /// is deliberate: it leaves the pre-existing behaviour of such halves exactly
  /// as it was — one is kept — rather than turning every old half into its own
  /// device and inventing a second speaker's worth of duplicates in rooms that
  /// already exist.
  final String? deviceId;

  /// Where this device's wall clock sat relative to the SFU's, read at join.
  ///
  /// OPTIONAL on the wire, in both directions. Events written before this
  /// existed carry nothing, other clients need not write it, and a reader that
  /// cannot use it loses only the cross-speaker CORRECTION -- `at_ms` still
  /// means what it always meant, an absolute Unix millisecond on the writing
  /// device's own clock, and every word is still shown. See [ClockAnchor].
  final ClockAnchor? clockAnchor;

  /// Whether this writer marks the positions it could not pin down.
  ///
  /// OPTIONAL on the wire, like [clockAnchor], and false when absent. It
  /// asserts one thing: a segment here carrying no `at_span_ms` was placed at
  /// its own first word. An older or foreign client has not said that, and
  /// absence of the claim is not the claim -- see
  /// [TranscriptHalf.positionsMarked].
  ///
  /// Defaults to false so that a caller which forgets it under-claims. The one
  /// writer that may set it is `transcript_writer.dart`, which builds the
  /// segments it describes.
  final bool positionsMarked;

  const CallTranscriptContent({
    required this.callKey,
    required this.segments,
    required this.accounting,
    this.langCode,
    this.deviceId,
    this.clockAnchor,
    this.positionsMarked = false,
  });

  /// The relation type and the event type are the same string: a transcript
  /// event relates to its call by being a transcript of it, and inventing a
  /// second name for that would be one more thing to keep in step.
  static const relType = 'pangea.call_transcript';

  /// What a READER will accept from one half, regardless of what the writer
  /// claims. Our own writer stays well under both (a half is capped at 50000
  /// bytes on the way out), so these only ever bite on content we did not
  /// write. Room content is untrusted: without a ceiling here, one event with a
  /// vast segment list makes opening a transcript do unbounded work, and a
  /// bogus half could win the duplicate contest in §_beats by sheer volume.
  static const maxSegments = 2000;
  static const maxTotalChars = 60000;

  /// How many RAW entries the reader will even look at.
  ///
  /// Separate from [maxSegments], which counts only the ones that parsed. A
  /// list of a million nulls accepts nothing and so never reached that cap,
  /// while still costing a full scan.
  static const maxRawEntries = 4000;

  /// The longest device id this reader will key a half by.
  ///
  /// A device id is an opaque short token — Synapse mints ten characters — and
  /// this value is a GROUPING KEY held in a map while a transcript is
  /// assembled. Room content is untrusted and an event has kilobytes of room
  /// in it, so the ceiling is here for the same reason [maxSegments] is: a
  /// bound on what one hostile event can make the reader hold.
  static const maxDeviceIdChars = 255;

  /// [raw] when it is a device id this reader will act on, and null otherwise.
  ///
  /// ONE rule, guarding the wire in both directions — [fromJson] reads through
  /// it, [toJson] writes through it, and [txnId] scopes through it. A value
  /// this reader would refuse is therefore never written, and never scopes a
  /// transaction id it is absent from.
  ///
  /// Empty is not a device. It would otherwise be a device id that reads as
  /// present and groups every half carrying it together, which is the absent
  /// case wearing a name.
  static String? usableDeviceId(Object? raw) =>
      raw is String && raw.isNotEmpty && raw.length <= maxDeviceIdChars
      ? raw
      : null;

  Map<String, dynamic> toJson() => {
    'call_key': callKey,
    'segments': [for (final segment in segments) segment.toJson()],
    ...accounting.toJson(),
    if (langCode != null) 'lang_code': langCode,
    'device_id': ?usableDeviceId(deviceId),
    if (positionsMarked) 'positions_marked': true,
    ...?clockAnchor?.toJson(),
    'm.relates_to': {'rel_type': relType, 'event_id': callKey},
  };

  /// Parses a transcript event's content.
  ///
  /// Tolerant on purpose: room content is untrusted and may come from an older
  /// or modified client, so a malformed segment is skipped and a malformed
  /// event returns null. Neither may take the transcript view down, and a
  /// partial read is always preferable to an exception — the reader's job is to
  /// show what can be shown and say what it could not.
  static CallTranscriptContent? fromJson(Map<String, dynamic> content) {
    final callKey = content['call_key'];
    if (callKey is! String || callKey.isEmpty) return null;

    final rawSegments = content['segments'];
    if (rawSegments is! List) return null;

    // Bounded as it is built, not filtered afterwards: the point is to stop
    // early, so a hostile list costs the reader a fixed amount of work.
    final segments = <TranscriptSegment>[];
    var totalChars = 0;
    var examined = 0;
    var shortened = rawSegments.length > maxRawEntries;
    var unreadable = false;

    // Starts as what the event claims and can only be taken AWAY below.
    //
    // A half that declares a span this reader cannot use has not told us which
    // of its positions are exact, whatever its flag says: the one entry we
    // could not read might have been the approximate one. Voiding the CLAIM is
    // the right cost -- the same shape `HalfAccounting.declared` uses -- and it
    // is why the span check cannot instead destroy the segment's `at_ms`, which
    // would drop the whole call to the per-speaker view over one corrupt byte.
    var positionsMarked = content['positions_marked'] == true;

    for (final raw in rawSegments) {
      if (examined >= maxRawEntries || segments.length >= maxSegments) {
        shortened = true;
        break;
      }
      examined++;

      // Checked before the entry is trimmed, which saves one copy of a hostile
      // string. Deliberately NOT covered by a test: the observable output is
      // identical either way, so any test would pass with this removed, and a
      // test that cannot fail is worse than none. Worth keeping as cheap
      // hygiene rather than protection -- by the time this runs the SDK has
      // already parsed the whole event into memory, so the allocation this
      // avoids is the second one, not the first.
      if (raw is Map &&
          raw['text'] is String &&
          (raw['text'] as String).length > maxTotalChars) {
        shortened = true;
        break;
      }

      final segment = TranscriptSegment.fromJson(raw);
      if (segment == null) {
        // Noted apart from the ceilings. Both shorten the half, and calling a
        // corrupt entry "too long to send" is a confident, specific, wrong
        // answer to somebody trying to work out what happened.
        unreadable = true;
        // A dropped entry is dropped CONTENT. Skipping it quietly and then
        // presenting the rest as whole is the same lie as truncating quietly,
        // and the reason does not matter to the person reading it.
        shortened = true;
        continue;
      }
      // Checked BEFORE adding, against this segment's own size: testing the
      // running total first let a single vast segment through whole.
      if (totalChars + segment.text.length > maxTotalChars) {
        shortened = true;
        break;
      }
      if (TranscriptSegment.spanOf(raw, segment.atMs).declaredButUnusable) {
        positionsMarked = false;
      }
      segments.add(segment);
      totalChars += segment.text.length;
    }

    final langCode = content['lang_code'];

    var accounting = HalfAccounting.fromJson(content);

    // The accounting and the content must agree, in BOTH directions. Only here
    // are the two visible at once, so this is the only place the disagreement
    // can be seen at all -- and a half whose own numbers contradict its own
    // words is not trustworthy about completeness either.
    //
    // The check used to name one direction. Naming one direction is how the
    // other goes unnoticed: this file already learned that once, when the
    // coherence rule named `transcribed` and stopped holding the moment
    // `lost` was added.
    //
    // Words with nothing behind them: it shipped speech while claiming to have
    // captured nothing.
    //
    // Nothing with words behind it: it claims a chunk was transcribed and
    // carries no words at all -- which would otherwise read as a flat,
    // uncaveated "they said nothing", a definite claim about a person
    // contradicted by the same event's own numbers. Truncation is the
    // legitimate way to be in that state, so it is excluded: a half whose
    // segments were dropped to fit says so, and already reads as incomplete.
    if (accounting.declared) {
      final wordsWithoutCapture =
          segments.isNotEmpty && accounting.chunksCaptured == 0;
      //
      // Excluded when WE shortened the half, not only when the writer did.
      // `accounting.truncated` here is the writer's own admission -- the
      // reader's version of that flag is not applied until below -- so a half
      // whose only segment this loop dropped as corrupt arrived at this test
      // with an empty list and was called impossible. That accuses the writer
      // of numbers that never disagreed with anything it sent, and it buries
      // the real cause, which is that we could not read what it sent.
      final captureWithoutWords =
          segments.isEmpty &&
          accounting.chunksTranscribed > 0 &&
          !accounting.truncated &&
          !shortened;

      // Words with nothing that produced them. Zero chunks transcribed means
      // no chunk yielded usable text, so text cannot exist -- unless the half
      // was shortened, where the words that remain came from chunks the count
      // no longer describes.
      final wordsWithoutTranscription =
          segments.isNotEmpty &&
          accounting.chunksTranscribed == 0 &&
          !accounting.truncated;

      // A microphone that never opened cannot have captured anything or
      // produced words. This check did not learn about `capture_refused` when
      // it was added, so a half could assert the mic never opened while
      // carrying real chunks and real text, and be believed -- the diagnosis
      // then confidently reported a microphone failure for a half whose own
      // numbers said otherwise.
      //
      // Total over every count the half carries, not over the two that were
      // obvious. It named chunksCaptured and visible segments, and missed
      // segments_omitted -- so a half could say the microphone never opened
      // AND that it dropped transcript segments to fit, which are produced
      // text, and be believed. This file has now made the same mistake twice:
      // a rule that enumerates SOME of the counts stops holding the moment
      // another is added, so this one names all of them.
      final refusedYetRecorded =
          accounting.captureRefused &&
          (accounting.chunksCaptured > 0 ||
              accounting.chunksTranscribed > 0 ||
              accounting.chunksLost > 0 ||
              accounting.chunksSuppressed > 0 ||
              // Named for the rule stated above rather than for reach: a
              // deferred chunk with nothing captured already fails the
              // captured-total check in `HalfAccounting.fromJson`, so this
              // term cannot today be the one that decides. It is here so the
              // enumeration stays complete if that check ever changes, and it
              // is deliberately not covered by a test -- one would pass with
              // this line removed.
              accounting.chunksDiscarded > 0 ||
              // This one DOES decide: dropped audio is milliseconds rather
              // than a share of the captured chunk total, so no other rule
              // sees it.
              accounting.captureDroppedMs > 0 ||
              accounting.segmentsOmitted > 0 ||
              segments.isNotEmpty);

      if (wordsWithoutCapture ||
          captureWithoutWords ||
          wordsWithoutTranscription ||
          refusedYetRecorded) {
        accounting = accounting.asIncoherent();
      }
    }

    return CallTranscriptContent(
      callKey: callKey,
      segments: segments,
      // A half the READER shortened must not read as whole. Dropping speech
      // and then presenting the remainder as complete is the one outcome this
      // feature cannot produce, and it does not matter whether the writer or
      // the reader did the dropping.
      accounting: !shortened
          ? accounting
          : unreadable
          ? accounting.readerFoundUnreadable()
          : accounting.readerTruncated(),
      langCode: langCode is String && langCode.isNotEmpty ? langCode : null,
      // A malformed device id is ABSENT, on the same terms as a malformed
      // anchor: it decides which halves of one account are grouped together,
      // and refusing the event over it would cost every word to save a
      // grouping. What it costs instead is stated where [deviceId] is declared
      // -- such a half keys alike with every other half that did not say.
      deviceId: usableDeviceId(content['device_id']),
      positionsMarked: positionsMarked,
      // A malformed anchor is ABSENT, never a reason to reject the half. It
      // decides only where these words sit against the OTHER speaker's, and
      // refusing an event over it would cost every word to save an ordering.
      clockAnchor: ClockAnchor.fromJson(content),
    );
  }

  /// The transaction id for sending this half.
  ///
  /// Deterministic in `(call_key, sender, device)` so that a RESEND after a
  /// network failure collapses server-side instead of writing a second copy of
  /// the same speech. It is not an update mechanism and nothing may treat it as
  /// one: the content is computed once, after the drain settles, so no attempt
  /// ever carries different bytes.
  ///
  /// The DEVICE is in the key because a resend is always from the same device,
  /// while two devices of one account in one call are two different halves of
  /// what that person said. Keyed by `(call_key, sender)` the id asserted a
  /// cardinality it was never entitled to: one half per ACCOUNT, when what it
  /// was ever protecting against was one device sending twice.
  ///
  /// A writer that cannot name its own device scopes to the empty segment,
  /// which is the same key every such writer uses. That costs nothing it was
  /// not already paying: a client that does not know its device id cannot tell
  /// its halves apart on the read side either, and it is one device.
  static String txnId(String callKey, String senderId, String? deviceId) =>
      'pangea.call_transcript:$callKey:$senderId:'
      '${usableDeviceId(deviceId) ?? ''}';
}

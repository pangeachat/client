import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';

/// The `pangea.call_transcript` event: one speaker's side of one call.
///
/// One event per speaker, never split into parts. Parts were the first design
/// and every review found another corner in them — a sequence counter that has
/// to survive process death across a rejoin, a declared part count a reader
/// must not trust, non-contiguous numbering from a buggy writer, and no clean
/// answer for what "absent" means while parts are still arriving. A half is one
/// event or it is missing, and both are decidable at a glance.
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

  const CallTranscriptContent({
    required this.callKey,
    required this.segments,
    required this.accounting,
    this.langCode,
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

  Map<String, dynamic> toJson() => {
    'call_key': callKey,
    'segments': [for (final segment in segments) segment.toJson()],
    ...accounting.toJson(),
    if (langCode != null) 'lang_code': langCode,
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
      final refusedYetRecorded =
          accounting.captureRefused &&
          (accounting.chunksCaptured > 0 || segments.isNotEmpty);

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
    );
  }

  /// The transaction id for sending this half.
  ///
  /// Deterministic in `(call_key, sender)` so that a RESEND after a network
  /// failure collapses server-side instead of writing a second copy of the same
  /// speech. It is not an update mechanism and nothing may treat it as one: the
  /// content is computed once, after the drain settles, so no attempt ever
  /// carries different bytes.
  static String txnId(String callKey, String senderId) =>
      'pangea.call_transcript:$callKey:$senderId';
}

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
    for (final raw in rawSegments) {
      if (segments.length >= maxSegments || totalChars >= maxTotalChars) break;
      final segment = TranscriptSegment.fromJson(raw);
      if (segment == null) continue;
      segments.add(segment);
      totalChars += segment.text.length;
    }

    final langCode = content['lang_code'];

    return CallTranscriptContent(
      callKey: callKey,
      segments: segments,
      accounting: HalfAccounting.fromJson(content),
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

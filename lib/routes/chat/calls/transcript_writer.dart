import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';

/// Sends one transcript half. Injected so the packing and refusal rules below
/// are testable without a homeserver.
typedef TranscriptSender =
    Future<void> Function(Map<String, dynamic> content, String txnId);

/// The byte ceiling for one half.
///
/// The repo's measured safe threshold: `maxPDUSize` is 60000, and a comment in
/// `room_analytics_extension.dart` records that the bare 60000 was still
/// rejected in practice, so events are packed under `maxPDUSize - 10000`.
const kMaxHalfBytes = 50000;

/// Publishes this device's half of a call.
///
/// Called once, AFTER the sink's drain has settled, so the content is final and
/// is never revised. Returns whether anything was written.
///
/// [callKey] is the caller's membership event id, which both sides know — the
/// anchor both halves relate to. Without it there is nothing to hang a half on
/// and nothing to query later, so no half is written at all: a half nobody can
/// find is worse than none, because it looks like the feature worked.
Future<bool> writeCallTranscript({
  required TranscriptSender send,
  required String? callKey,
  required String senderId,
  required List<TranscriptSegment> segments,
  required int chunksCaptured,
  required int chunksTranscribed,
  required bool drainComplete,
  String? langCode,
  int maxBytes = kMaxHalfBytes,
}) async {
  if (callKey == null || callKey.isEmpty) {
    Logs().w('No call transcript written: the call has no anchor to relate to');
    return false;
  }

  // A speaker who captured nothing still writes, and deliberately so: an empty
  // half is a real answer -- they were muted, or said nothing -- and it is a
  // DIFFERENT answer from no half at all, which means we do not know. The
  // reader can only tell those apart if the silent case is stated.
  final packed = _packUnder(segments, maxBytes);

  final content = CallTranscriptContent(
    callKey: callKey,
    segments: packed.segments,
    accounting: HalfAccounting(
      chunksCaptured: chunksCaptured,
      chunksTranscribed: chunksTranscribed,
      truncated: packed.omitted > 0,
      segmentsOmitted: packed.omitted,
      drainComplete: drainComplete,
      // Our own halves always carry a full accounting, so a round-trip of one
      // never reads back as a writer that asserted nothing.
      declared: true,
    ),
    langCode: langCode,
  );

  await send(content.toJson(), CallTranscriptContent.txnId(callKey, senderId));
  return true;
}

/// Drops segments from the TAIL until the half fits.
///
/// From the tail because the beginning of a conversation is the part a reader
/// needs to make sense of the rest; losing the end of a long call is bad, and
/// losing its start is worse. The count of what went is carried in the half's
/// accounting, so a truncated transcript says so rather than presenting itself
/// as everything that was said.
({List<TranscriptSegment> segments, int omitted}) _packUnder(
  List<TranscriptSegment> segments,
  int maxBytes,
) {
  final kept = <TranscriptSegment>[];
  // The envelope around the segments -- keys, accounting, the relation -- is
  // charged for before any segment is, so a half cannot fit its text and then
  // overflow on its own metadata.
  var used = _envelopeBytes;

  for (final segment in segments) {
    final cost = _segmentBytes(segment);
    if (used + cost > maxBytes) break;
    kept.add(segment);
    used += cost;
  }

  return (segments: kept, omitted: segments.length - kept.length);
}

/// A conservative allowance for everything in the event that is not a segment.
const _envelopeBytes = 512;

/// What one segment costs on the wire, counted in UTF-8 bytes rather than
/// characters: a transcript of a non-Latin language would otherwise be measured
/// at a fraction of its real size and blow the ceiling it was checked against.
int _segmentBytes(TranscriptSegment segment) =>
    // The JSON shape {"text":"..."} plus its separator, near enough.
    12 + _utf8Length(segment.text);

int _utf8Length(String text) {
  var bytes = 0;
  for (final rune in text.runes) {
    if (rune <= 0x7F) {
      bytes += 1;
    } else if (rune <= 0x7FF) {
      bytes += 2;
    } else if (rune <= 0xFFFF) {
      bytes += 3;
    } else {
      bytes += 4;
    }
  }
  return bytes;
}

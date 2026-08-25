import 'dart:convert';

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
  required int chunksLost,
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
  // Built through a closure so packing measures the REAL event, accounting and
  // relation included, rather than guessing at the envelope around the text.
  CallTranscriptContent build(List<TranscriptSegment> kept, int omitted) =>
      CallTranscriptContent(
        callKey: callKey,
        segments: kept,
        accounting: HalfAccounting(
          chunksCaptured: chunksCaptured,
          chunksTranscribed: chunksTranscribed,
          chunksLost: chunksLost,
          truncated: omitted > 0,
          segmentsOmitted: omitted,
          drainComplete: drainComplete,
          // Our own halves always carry a full accounting, so a round-trip of
          // one never reads back as a writer that asserted nothing.
          declared: true,
        ),
        langCode: langCode,
      );

  // Sized against the worst case for the accounting fields: a half packed while
  // claiming nothing was omitted, then re-labelled as truncated, would grow by
  // the extra digits and could cross the line it was just checked against.
  final packed = _packUnder(
    segments,
    maxBytes,
    (kept) => build(kept, segments.length - kept.length),
  );
  final content = build(packed.segments, packed.omitted);

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
///
/// The fit is MEASURED, not estimated. An earlier version added up UTF-8 byte
/// lengths, which undercounts what actually goes on the wire: the event is
/// serialised as JSON, where a quote costs two bytes, a newline two, and a
/// control character six. A half could therefore be packed, believed to be
/// under budget, and still be rejected by the server -- losing the whole half
/// rather than its tail, which is the outcome the packing exists to avoid.
///
/// Found by binary search over the prefix length, so a long half costs a
/// handful of encodings rather than one per segment.
({List<TranscriptSegment> segments, int omitted}) _packUnder(
  List<TranscriptSegment> segments,
  int maxBytes,
  CallTranscriptContent Function(List<TranscriptSegment>) build,
) {
  if (_encodedBytes(build(segments)) <= maxBytes) {
    return (segments: segments, omitted: 0);
  }

  // Largest prefix that fits. `low` is always known to fit and `high` always
  // known not to, so the loop cannot settle on an over-budget answer.
  var low = 0;
  var high = segments.length;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    if (_encodedBytes(build(segments.sublist(0, mid))) <= maxBytes) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }

  return (segments: segments.sublist(0, low), omitted: segments.length - low);
}

int _encodedBytes(CallTranscriptContent content) =>
    utf8.encode(jsonEncode(content.toJson())).length;

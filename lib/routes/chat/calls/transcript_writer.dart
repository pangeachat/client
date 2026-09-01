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

/// How much larger an event gets once the room encrypts it.
///
/// Megolm wraps the plaintext and the result is base64, which costs a third
/// again, plus a fixed envelope. Measured against the PLAINTEXT here because
/// that is all the writer can see: it hands content to a sender, and whether
/// that sender encrypts is the room's business, not the packer's.
///
/// Without this the packer fits a half to 50000 bytes of plaintext, the room
/// inflates it past the server's ceiling, and the server rejects the WHOLE
/// half -- not its tail. A retry re-packs from the same frozen segments to the
/// same wrong budget, so the loss is permanent rather than transient.
///
/// Pangea creates its rooms unencrypted, so this is defence for a room we did
/// not make. Deliberately generous: over-packing loses everything, and
/// under-packing loses a few sentences off the end and says so.
const kEncryptedOverheadFactor = 1.4;

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

  /// Which of this account's devices is writing. Required rather than
  /// defaulted, like every count beside it: a caller that omitted it would
  /// publish a half indistinguishable from the other device's, and the reader
  /// would keep one of the two. Null is a first-class answer for a client that
  /// cannot name its own device -- the field is then simply left off the event.
  required String? deviceId,
  required List<TranscriptSegment> segments,
  required int chunksCaptured,
  required int chunksTranscribed,
  required int chunksLost,
  required int chunksSuppressed,
  required int chunksDiscarded,

  // How much audio the capture path lost before it could become a chunk.
  // Required rather than defaulted, like every count beside it: zero is a
  // claim that nothing went, and a caller that forgot this would publish a
  // clean half over a hole in the recording.
  required int captureDroppedMs,
  required bool captureRefused,
  required bool drainComplete,
  String? langCode,

  /// Where this device's clock sat relative to the SFU's, or null when the two
  /// could not be read together. Null is a first-class answer and is simply
  /// omitted from the event: a half that cannot say how its clock compared is
  /// exactly the half a reader must not correct.
  ClockAnchor? clockAnchor,
  bool encrypted = false,
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
          chunksSuppressed: chunksSuppressed,
          chunksDiscarded: chunksDiscarded,
          captureDroppedMs: captureDroppedMs,
          captureRefused: captureRefused,
          truncated: omitted > 0,
          segmentsOmitted: omitted,
          drainComplete: drainComplete,
          // Our own halves always carry a full accounting, so a round-trip of
          // one never reads back as a writer that asserted nothing.
          declared: true,
        ),
        langCode: langCode,
        deviceId: deviceId,
        // These two are inside the closure with everything else, so the packer
        // measures the event that actually goes on the wire. Sizing without a
        // field and adding it afterwards would grow a half past the budget it
        // was just checked against, and the server rejects the WHOLE half
        // rather than its tail.
        clockAnchor: clockAnchor,
        // Always, and only here. `buildSegments` marks every position it could
        // not pin down to a word, so a half from this writer carries the claim
        // that a segment with no span WAS pinned to one. No other caller may
        // set it: the flag describes how the segments were built, and this is
        // the only place that knows.
        positionsMarked: true,
      );

  // Sized against the worst case for the accounting fields: a half packed while
  // claiming nothing was omitted, then re-labelled as truncated, would grow by
  // the extra digits and could cross the line it was just checked against.
  final budget = encrypted
      ? (maxBytes / kEncryptedOverheadFactor).floor()
      : maxBytes;

  final packed = _packUnder(
    segments,
    budget,
    (kept) => build(kept, segments.length - kept.length),
  );
  final content = build(packed.segments, packed.omitted);

  // Checked, not assumed. Packing trims SEGMENTS, so it can only shrink a half
  // down to its envelope -- call key, accounting, relation, language tag. If
  // the envelope alone is over budget the binary search converges on zero
  // segments and returns an empty half that is still too large, silently,
  // because nothing downstream looks again. Sending it means the server
  // rejects the WHOLE half, which is the outcome the packing exists to avoid.
  final encoded = _encodedBytes(content);
  if (encoded > budget) {
    Logs().e(
      'No call transcript written: the half does not fit even with every '
      'segment dropped ($encoded > $budget bytes)',
    );
    return false;
  }

  await send(
    content.toJson(),
    CallTranscriptContent.txnId(callKey, senderId, deviceId),
  );
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

import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';

/// Sends one full-call merge, returning the event id the homeserver assigned
/// (or null, on the same terms [CallAudioSender] in `call_audio_writer.dart`
/// itself does). Injected so the building and refusal rules below are
/// testable without a homeserver -- exactly what [CallAudioSender] is for the
/// per-device half.
typedef CallAudioMergedSender =
    Future<String?> Function(Map<String, dynamic> content, String txnId);

/// Publishes a full-call merged recording.
///
/// Called once the merge's bytes have already been mixed (`call_audio_merge.dart`)
/// and uploaded, with the URL that upload produced -- the same shape
/// `writeCallAudioEvent` takes for a per-device half, and for the same reason:
/// there is no byte budget to pack against here either, the content is a
/// handful of fixed fields plus a URL, never the recording's own bytes.
///
/// Returns the sent event's id, or null when [send] itself returned null, OR
/// when [callKey] is absent or empty, OR when [sourceEventIds] is empty once
/// sanitised (see [CallAudioMergedContent.canonicalSourceEventIds]) -- a merge
/// nobody could relate to a call, or that names no coverage at all, is worse
/// than no merge, because it looks like the feature worked while leaving
/// nothing a reader could act on. [send] THROWING is a distinct outcome this
/// function does not catch: exactly [writeCallAudioEvent]'s own rule, the
/// caller decides what a failed attempt means.
Future<String?> writeCallAudioMergedEvent({
  required CallAudioMergedSender send,
  required String? callKey,
  required String url,
  required String mimetype,
  required int size,
  required int durationMs,
  required int sampleRate,
  required int channels,
  required List<String> sourceEventIds,
  String codec = kCallAudioCodec,
  int? mergedStartSfuMs,
}) async {
  if (callKey == null || callKey.isEmpty) {
    Logs().w(
      'No call audio merge written: the call has no anchor to relate to',
    );
    return null;
  }

  final coverage = CallAudioMergedContent.canonicalSourceEventIds(
    sourceEventIds,
  );
  if (coverage.isEmpty) {
    Logs().w(
      'No call audio merge written: it covers no source halves once '
      'sanitised',
    );
    return null;
  }

  final content = CallAudioMergedContent(
    callKey: callKey,
    url: url,
    mimetype: mimetype,
    size: size,
    durationMs: durationMs,
    sampleRate: sampleRate,
    channels: channels,
    codec: codec,
    mergedStartSfuMs: mergedStartSfuMs,
    sourceEventIds: sourceEventIds,
  );

  return send(
    content.toJson(),
    CallAudioMergedContent.txnId(callKey, sourceEventIds),
  );
}

// Package imports:
import 'package:matrix/matrix.dart';

// Project imports:
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

/// Sends one call-audio half. Injected so the building and refusal rules below
/// are testable without a homeserver -- exactly what [TranscriptSender] is for
/// the transcript half in `transcript_writer.dart`.
typedef CallAudioSender =
    Future<void> Function(Map<String, dynamic> content, String txnId);

/// Publishes this device's call-audio half.
///
/// Called once the recording has already been uploaded, with the URL that
/// upload produced. Unlike `writeCallTranscript` there is no byte budget to
/// pack against here: the content is a handful of fixed fields plus a URL,
/// never the recording's own bytes, so nothing about this event grows with
/// how long the call was.
///
/// Returns whether anything was written. `false` only when [callKey] is
/// absent or empty -- there is then nothing to relate this half to, and a
/// half nobody could find is worse than no half at all, because it looks like
/// the feature worked.
Future<bool> writeCallAudioEvent({
  required CallAudioSender send,
  required String? callKey,
  required String senderId,
  required String? deviceId,
  required String url,
  required String mimetype,
  required int size,
  required int durationMs,
  required int sampleRate,
  required int channels,
  String codec = kCallAudioCodec,
  ClockAnchor? clockAnchor,
  int? recordingStartedOffsetFromDeviceJoinMs,
}) async {
  if (callKey == null || callKey.isEmpty) {
    Logs().w('No call audio written: the call has no anchor to relate to');
    return false;
  }

  final content = CallAudioContent(
    callKey: callKey,
    deviceId: deviceId,
    url: url,
    mimetype: mimetype,
    size: size,
    durationMs: durationMs,
    sampleRate: sampleRate,
    channels: channels,
    codec: codec,
    clockAnchor: clockAnchor,
    recordingStartedOffsetFromDeviceJoinMs:
        recordingStartedOffsetFromDeviceJoinMs,
  );

  await send(
    content.toJson(),
    CallAudioContent.txnId(callKey, senderId, deviceId),
  );
  return true;
}

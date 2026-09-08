// Package imports:
import 'package:matrix/matrix.dart';

// Project imports:
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

/// Sends one call-audio half, returning the event id the homeserver assigned
/// (or null, on the same terms `CallEventSender` in `call_record.dart` and
/// `Client.sendEvent` itself do). Injected so the building and refusal rules
/// below are testable without a homeserver -- exactly what [TranscriptSender]
/// is for the transcript half in `transcript_writer.dart`.
typedef CallAudioSender =
    Future<String?> Function(Map<String, dynamic> content, String txnId);

/// Publishes this device's call-audio half.
///
/// Called once the recording has already been uploaded, with the URL that
/// upload produced. Unlike `writeCallTranscript` there is no byte budget to
/// pack against here: the content is a handful of fixed fields plus a URL,
/// never the recording's own bytes, so nothing about this event grows with
/// how long the call was.
///
/// Returns the sent event's id, or null when [send] itself returned null, OR
/// when [callKey] is absent or empty -- there is then nothing to relate this
/// half to, and a half nobody could find is worse than no half at all,
/// because it looks like the feature worked. [send] THROWING is a distinct
/// outcome this function does not catch: the caller's own retry loop
/// (`CallAudioRecorder.finish`) is what decides what a failed attempt means.
Future<String?> writeCallAudioEvent({
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
  bool truncated = false,
}) async {
  if (callKey == null || callKey.isEmpty) {
    Logs().w('No call audio written: the call has no anchor to relate to');
    return null;
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
    truncated: truncated,
  );

  return send(
    content.toJson(),
    CallAudioContent.txnId(callKey, senderId, deviceId),
  );
}

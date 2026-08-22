import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// One stretch of this device's own outbound call audio.
///
/// Signed 16-bit samples, one channel, in the order the machine writes them.
/// The rate is carried rather than assumed: the audio processing module picks it
/// from the device and the negotiated codec, and it can change mid-call.
class CallAudioFrame {
  final Uint8List pcm16;
  final int sampleRate;

  const CallAudioFrame({required this.pcm16, required this.sampleRate});
}

/// Reads this device's own outbound call audio after echo cancellation.
///
/// Android only, and only because Android needs it. Its ordinary track sink
/// fires on the raw microphone buffer, before echo cancellation runs, so a
/// recording made there also contains the other person coming back out of the
/// loudspeaker — and every word that bled through would be credited to the wrong
/// learner. Every other platform this app ships on already taps after that
/// processing, so there is nothing for this to do there.
class PangeaCallCapture {
  static const MethodChannel _control =
      MethodChannel('pangea.chat/call_capture');
  static const EventChannel _frames = EventChannel(
    'pangea.chat/call_capture/frames',
  );

  const PangeaCallCapture();

  /// Begins delivering frames.
  ///
  /// False when the platform side could not attach — the WebRTC plugin not being
  /// up yet, most likely. The caller records nothing in that case, which costs
  /// analytics; failing the call instead would cost the conversation.
  Future<bool> start() async =>
      await _control.invokeMethod<bool>('start') ?? false;

  Future<void> stop() => _control.invokeMethod<void>('stop');

  /// The frames themselves.
  ///
  /// ONE platform subscription, shared by every listener. Each call to
  /// receiveBroadcastStream makes its own platform subscription, and the
  /// native side holds a single sink slot whose onCancel clears it
  /// unconditionally -- so two concurrent listeners (a stale, overtaken start
  /// still winding down beside the live recording) let the stale one's cancel
  /// clear the LIVE recording's sink, and every frame after that was dropped
  /// in silence. A single shared broadcast stream is reference-counted by
  /// Dart: the platform subscription ends only when the LAST listener goes.
  static final Stream<CallAudioFrame> _sharedFrames = _frames
      .receiveBroadcastStream()
      .map((event) {
        final map = event as Map;
        return CallAudioFrame(
          pcm16: map['pcm'] as Uint8List,
          sampleRate: map['sampleRate'] as int,
        );
      })
      .asBroadcastStream();

  Stream<CallAudioFrame> get frames => _sharedFrames;
}

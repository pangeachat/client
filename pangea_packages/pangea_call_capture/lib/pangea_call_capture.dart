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
  /// ONE platform subscription, shared by every listener, opened on the first
  /// and closed on the last. Each receiveBroadcastStream call makes its own
  /// platform subscription, and the native side holds a single sink slot whose
  /// onCancel clears it unconditionally -- so two concurrent listeners (a
  /// stale, overtaken start winding down beside the live recording) let the
  /// stale one's cancel clear the LIVE recording's sink, and every frame after
  /// that was dropped in silence.
  ///
  /// A broadcast CONTROLLER rather than asBroadcastStream: the latter pins its
  /// source for ever once listened, which would hold the native sink open for
  /// the life of the app. The controller's onListen/onCancel fire on the first
  /// and last listener, giving real reference counting that also survives
  /// everyone leaving and a later call listening afresh.
  static StreamSubscription<dynamic>? _platformSub;

  /// The previous platform cancel, still in flight.
  ///
  /// A new first-listener can arrive while the last-listener's cancel is still
  /// travelling to the platform; opening a fresh subscription right away lets
  /// the OLD cancel land afterwards and clear the native sink under the new
  /// one -- the same single-sink failure this stream exists to prevent, moved
  /// across a listener gap. Every listen therefore queues behind the cancel
  /// before it. The cost is a few first frames dropped into a null native sink
  /// while the deferred listen lands -- milliseconds of leading silence; the
  /// alternative was a live recording going silent for good.
  static Future<void> _settling = Future.value();

  static final StreamController<CallAudioFrame> _shared =
      StreamController<CallAudioFrame>.broadcast(
    onListen: () {
      _settling = _settling.then((_) {
        // Everyone may already have left while this waited its turn.
        if (!_shared.hasListener) return null;
        _platformSub = _frames.receiveBroadcastStream().listen(
          (event) {
            final map = event as Map;
            _shared.add(
              CallAudioFrame(
                pcm16: map['pcm'] as Uint8List,
                sampleRate: map['sampleRate'] as int,
              ),
            );
          },
          onError: _shared.addError,
        );
        return null;
      })
          // Absorbed so the chain stays alive. Every listen and cancel queues
          // on this one future; left failed, it would fail every one of them
          // for the rest of the app's life, and no call would record again.
          .catchError(_settlingFailed);
    },
    onCancel: () async {
      _settling = _settling.then((_) {
        final sub = _platformSub;
        _platformSub = null;
        return sub?.cancel();
      }).catchError(_settlingFailed);
      await _settling;
    },
  );

  Stream<CallAudioFrame> get frames => _shared.stream;

  /// One failed platform listen or cancel is that operation lost, and it is
  /// logged by the caller that notices the silence; it must never be every
  /// FUTURE operation lost too.
  static Null _settlingFailed(Object error, StackTrace stack) {
    // Deliberately swallowed after surfacing to listeners where possible: the
    // controller may have nobody left to tell, and the chain must settle.
    if (_shared.hasListener) _shared.addError(error, stack);
    return null;
  }
}

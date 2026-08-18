import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart' hide Room;
import 'package:matrix/matrix.dart' as matrix show Room;

import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';

enum CallStage {
  /// Joining the session, connecting media, and starting to record.
  connecting,

  /// Media is flowing and this device is announced to the room.
  connected,

  /// Left cleanly. The recording, if any, has been flushed.
  ended,

  /// Could not be established. Anything partially set up has been torn down.
  failed,
}

/// One call, from tapping Call to hanging up.
///
/// Exists as its own object rather than as widget state because the ordering
/// here is the whole feature: three subsystems come up in a sequence that
/// matters, and they have to come down even when one of them fails. A widget
/// disposing mid-teardown would leave a microphone open or a membership
/// advertised for a call nobody is in.
class ActiveCall extends ChangeNotifier {
  final CallService calls;
  final CallMedia media;
  final CallCaptureService capture;

  CallStage _stage = CallStage.connecting;
  Object? _error;
  bool _joined = false;
  bool _capturing = false;
  Future<void>? _hangUp;

  ActiveCall({required this.calls, required this.media, required this.capture});

  CallStage get stage => _stage;
  Object? get error => _error;
  bool get isRecording => _capturing;

  void _to(CallStage next, [Object? error]) {
    if (_stage == next && error == null) return;
    _stage = next;
    _error = error;
    notifyListeners();
  }

  /// Brings the call up.
  ///
  /// The order is deliberate. Media connects before this device announces
  /// itself, so a peer never sees a participant who cannot yet be heard, and
  /// recording starts before the announcement too — otherwise the first seconds
  /// of a call, which is exactly when people speak, would go uncredited.
  ///
  /// A failure at any step tears down the steps that already succeeded. The call
  /// either exists completely or not at all.
  Future<void> start(matrix.Room room, {required bool video}) async {
    try {
      final grant = await calls.join(room);
      _joined = true;
      await media.connect(grant, video: video);

      final track = media.publishedAudio;
      if (track != null) {
        capture.start(track);
        _capturing = true;
      } else {
        // The call is still worth having without analytics; a call that refuses
        // to connect because it cannot be recorded is the worse failure.
        Logs().w('Call has no published audio track; not recording');
      }

      await calls.announce();
      _to(CallStage.connected);
    } catch (e, s) {
      Logs().e('Could not start the call', e, s);
      await _tearDown();
      _to(CallStage.failed, e);
    }
  }

  /// Ends the call.
  ///
  /// Idempotent and safe to race: a user tapping hang up while the peer's
  /// departure is already tearing the call down joins the same teardown rather
  /// than starting a second one.
  Future<void> hangUp() => _hangUp ??= () async {
    await _tearDown();
    _to(CallStage.ended);
  }();

  /// Unwinds whatever is up, in reverse, and never gives up partway.
  ///
  /// Each step is isolated: a recording that fails to flush must not leave the
  /// microphone open, and a socket that fails to close must not leave this
  /// device advertised as a participant in a call it has left.
  Future<void> _tearDown() async {
    if (_capturing) {
      _capturing = false;
      try {
        await capture.stop();
      } catch (e, s) {
        Logs().e('Could not flush the call recording', e, s);
      }
    }

    try {
      await media.dispose();
    } catch (e, s) {
      Logs().e('Could not release the call media', e, s);
    }

    if (_joined) {
      _joined = false;
      try {
        await calls.retract();
      } catch (e, s) {
        Logs().e('Could not retract the call membership', e, s);
      }
    }
  }

  @override
  void dispose() {
    unawaited(hangUp());
    super.dispose();
  }
}

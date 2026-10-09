import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:fluffychat/utils/platform_infos.dart';

/// A ring the iOS call screen is showing, as the push described it.
class CallScreenRing {
  /// The call screen's own id for it.
  final String uuid;
  final String roomId;
  final String eventId;

  /// The account's client name, as its VoIP pusher tagged the push. Every
  /// account on the phone shares one VoIP token, so this is what says which
  /// account the call is for. Empty when the push carried none.
  final String account;

  const CallScreenRing({
    required this.uuid,
    required this.roomId,
    required this.eventId,
    required this.account,
  });

  factory CallScreenRing.fromMap(Map<Object?, Object?> map) => CallScreenRing(
    uuid: map['uuid'] as String? ?? '',
    roomId: map['roomId'] as String? ?? '',
    eventId: map['eventId'] as String? ?? '',
    account: map['account'] as String? ?? '',
  );
}

/// Why the app ended a call on the call screen. Shown by the system, which
/// words each one itself.
enum CallScreenEndReason {
  remoteEnded,
  unanswered,
  answeredElsewhere,
  declinedElsewhere,
  failed,
}

/// The learner ended a call on the call screen.
class CallScreenEnd {
  final CallScreenRing ring;

  /// Whether they had answered it: hanging up a call, rather than declining a
  /// ring.
  final bool answered;

  const CallScreenEnd(this.ring, {required this.answered});
}

/// The iOS call screen (CallKit), woken by a VoIP push (PushKit). iOS only.
///
/// The native side puts a ring on the call screen from the push alone, before
/// any Dart has run -- Apple requires it -- and hands it here. Everything after
/// that is the app's: whether the ring still rings, answering, declining, and
/// ending the call screen once the ring or the call it became is over. Design:
/// voice-video-calls.instructions.md, "Ringing when the app is closed".
class IosCallScreen {
  IosCallScreen._();

  /// For tests, which stand in for the call screen with a subclass and feed
  /// it events through [receive].
  @visibleForTesting
  IosCallScreen.forTesting();

  static final instance = IosCallScreen._();

  static const _channel = MethodChannel('chat.pangea/call_screen');

  final _rings = StreamController<CallScreenRing>.broadcast();
  final _answers = StreamController<CallScreenRing>.broadcast();
  final _ends = StreamController<CallScreenEnd>.broadcast();
  final _mutes = StreamController<bool>.broadcast();

  /// This phone's VoIP push token, base64, once PushKit has issued it.
  final voipToken = ValueNotifier<String?>(null);

  Future<void>? _listening;

  /// Rings the call screen put up, including any from before [listen].
  Stream<CallScreenRing> get rings => _rings.stream;

  /// Rings the learner answered on the call screen.
  Stream<CallScreenRing> get answers => _answers.stream;

  /// Calls the learner ended on the call screen.
  Stream<CallScreenEnd> get ends => _ends.stream;

  /// The learner muted (true) or unmuted the call from the call screen.
  Stream<bool> get mutes => _mutes.stream;

  /// Starts receiving the call screen's events, including those from before
  /// this was called: the app is usually launched BY the push.
  Future<void> listen() => _listening ??= _listen();

  Future<void> _listen() async {
    if (!PlatformInfos.isIOS) return;
    _channel.setMethodCallHandler(_onCall);
    voipToken.value = await _channel.invokeMethod<String>('listen');
  }

  /// An event from the call screen, as the platform delivers it.
  @visibleForTesting
  Future<void> receive(MethodCall call) => _onCall(call);

  Future<void> _onCall(MethodCall call) async {
    final args = call.arguments is Map
        ? call.arguments as Map<Object?, Object?>
        : const <Object?, Object?>{};
    switch (call.method) {
      case 'token':
        voipToken.value = args['token'] as String?;
      case 'incoming':
        _rings.add(CallScreenRing.fromMap(args));
      case 'answer':
        _answers.add(CallScreenRing.fromMap(args));
      case 'end':
        _ends.add(
          CallScreenEnd(
            CallScreenRing.fromMap(args),
            answered: args['answered'] == true,
          ),
        );
      case 'mute':
        _mutes.add(args['muted'] == true);
    }
  }

  /// Takes a call off the call screen: its ring is over, or the call it
  /// became has ended.
  Future<void> end(String uuid, CallScreenEndReason reason) =>
      _channel.invokeMethod<void>('end', {'uuid': uuid, 'reason': reason.name});

  /// Corrects the call screen once the app has read the ring: the push does
  /// not say whether the call is video.
  Future<void> setVideo(String uuid, bool video) =>
      _channel.invokeMethod<void>('update', {'uuid': uuid, 'video': video});
}

import 'package:flutter/foundation.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart';

import 'package:fluffychat/routes/chat/calls/call_presence.dart';

/// The SDK's handle on platform WebRTC and on call lifecycle callbacks.
///
/// Most of this interface exists for the legacy 1:1 and mesh paths. On the LiveKit
/// path the SDK does Matrix-side signalling only — it creates no peer connection, no
/// media stream, and never touches the microphone — so several members below are
/// never invoked. They are implemented honestly rather than left to throw, because a
/// call arriving on an unexpected path should degrade, not crash.
class PangeaVoipDelegate implements WebRTCDelegate {
  /// Which calls this client believes are live. The rules it encodes are tested
  /// directly in call_presence_test.dart; see that file for why they matter.
  final CallPresence _presence = CallPresence();

  /// Set while a legacy 1:1 call is up. Group-call presence is tracked separately,
  /// since those arrive and depart through different callbacks.
  bool _inLegacyCall = false;

  /// Notified when the set of known group calls changes, so the UI can react without
  /// this class importing widgets.
  void Function(GroupCallSession call)? onGroupCallDiscovered;
  final void Function(GroupCallSession call)? onGroupCallEnded;
  final void Function(CallSession call)? onIncomingCall;
  final void Function(CallSession call)? onCallEnded;

  PangeaVoipDelegate({
    this.onGroupCallDiscovered,
    this.onGroupCallEnded,
    this.onIncomingCall,
    this.onCallEnded,
  });

  /// Must be usable the moment `VoIP(client, delegate)` is constructed: the SDK
  /// dereferences this inside its constructor to attach a device-change listener.
  /// A lazily-built value here fails at construction, not at call time.
  @override
  MediaDevices get mediaDevices => webrtc.navigator.mediaDevices;

  @override
  Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) => webrtc.createPeerConnection(configuration, constraints);

  @override
  bool get isWeb => kIsWeb;

  @override
  bool get canHandleNewCall => !_inLegacyCall && !_presence.isBusy;

  /// Null by design. A key provider is only meaningful with MatrixRTC encryption,
  /// which v1 disables: Pangea rooms are unencrypted, MSC4143 forbids encryption
  /// there, and the call is transcribed by design.
  ///
  /// The SDK tolerates null on the normal path (`keyProvider?.onSetEncryptionKey`)
  /// but throws on the ratcheting path. Ratcheting only runs when
  /// `enableSFUE2EEKeyRatcheting` is set, which we leave off — so null is safe here
  /// only as long as encryption stays off. If e2ee is ever enabled, this must be
  /// implemented in the same change.
  @override
  EncryptionKeyProvider? get keyProvider => null;

  // --- 1:1 / mesh path -------------------------------------------------------
  // Not exercised by LiveKit calls. Implemented so an unexpected legacy invite
  // degrades quietly instead of throwing inside the SDK's sync handler.

  @override
  Future<void> playRingtone() async {}

  @override
  Future<void> stopRingtone() async {}

  @override
  Future<void> registerListeners(CallSession session) async {}

  @override
  Future<void> handleNewCall(CallSession session) async {
    _inLegacyCall = true;
    onIncomingCall?.call(session);
  }

  @override
  Future<void> handleCallEnded(CallSession session) async {
    _inLegacyCall = false;
    onCallEnded?.call(session);
  }

  @override
  Future<void> handleMissedCall(CallSession session) async {}

  // --- MatrixRTC path --------------------------------------------------------

  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {
    // Deliberately NOT filtered by [_presence]. A call id is derived from the
    // room, so every call in a conversation shares one — and a call that was
    // declined never reaches handleGroupCallEnded to clear it. Suppressing
    // repeats here meant declining once stopped that conversation ever ringing
    // again.
    //
    // Whether a discovery is worth announcing is decided by whoever listens,
    // from live membership rather than from what has been seen before.
    _presence.add(groupCall.groupCallId);
    onGroupCallDiscovered?.call(groupCall);
  }

  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {
    _presence.remove(groupCall.groupCallId);
    onGroupCallEnded?.call(groupCall);
  }

  @visibleForTesting
  CallPresence get presence => _presence;
}

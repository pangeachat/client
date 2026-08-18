import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart';
import 'package:matrix/matrix.dart' show Logs;

import 'package:fluffychat/routes/chat/calls/call_roster.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';

/// This device's media for one call.
///
/// The Matrix session says a call exists and who is in it; this connects the
/// audio and video to it. The two are deliberately separate — the SDK owns the
/// membership and never touches the microphone, so opening the capture device,
/// publishing it, and tearing it down is the app's job.
class CallMedia {
  final Room room;

  /// Capture options for the microphone.
  ///
  /// Echo cancellation is stated rather than inherited. It is the default, but
  /// the whole attribution guarantee rests on it: without it this device
  /// publishes the peer's voice back into the call, and every word that bled
  /// through would be transcribed as the wrong learner's.
  static const microphone = AudioCaptureOptions(
    echoCancellation: true,
    noiseSuppression: true,
  );

  bool _released = false;

  CallMedia({Room? room}) : room = room ?? Room();

  /// The audio this device is publishing, or null before the microphone is on.
  ///
  /// This is the track to record. It is the published one, already through echo
  /// cancellation, and it is acquired once and shared — recording must never
  /// open a second microphone of its own.
  ///
  /// Typed as [AudioTrack] rather than the concrete local track: that is the
  /// mixin carrying the capture API, so it is the narrowest type the recorder
  /// needs and the one the seam should be stated in.
  AudioTrack? get publishedAudio => room
      .localParticipant
      ?.audioTrackPublications
      .map((p) => p.track)
      .whereType<LocalAudioTrack>()
      .firstOrNull;

  bool get isConnected => room.connectionState == ConnectionState.connected;

  /// The SFU's view of who is in this call.
  ///
  /// Built here because this object owns the LiveKit room the roster reads, and
  /// presence must come from the same connection the media does. Overridable so
  /// a test can supply a roster without standing up a real connection.
  CallRoster roster({required String myUserId}) =>
      CallRoster(room: room, myUserId: myUserId);

  /// Connects to the SFU and publishes this device's media.
  ///
  /// Audio is published before video and awaited, so a caller can start
  /// recording the moment this returns rather than polling for a track that
  /// may still be negotiating.
  /// Connecting is several round-trips, and a hangup can land inside any of
  /// them. Each step checks first, so a call the user abandoned never ends up
  /// opening a microphone or a camera after teardown has run.
  Future<void> connect(CallToken grant, {required bool video}) async {
    if (_released) return;
    await connectRoom(grant.url, grant.jwt);
    if (_released) return _releaseWhatOpened();

    await enableMicrophone(true);
    if (_released) return _releaseWhatOpened();

    if (!video) return;
    await enableCamera(true);
    if (_released) return _releaseWhatOpened();
  }

  /// Releases anything a step finished opening after teardown had already run.
  ///
  /// Checking before each step is not enough on its own: a hangup landing while
  /// `enableMicrophone` is in flight cannot stop it, so the microphone opens
  /// anyway and simply returning would leave it open with nothing left to close
  /// it. Reconciling after each step is what makes the check sufficient.
  Future<void> _releaseWhatOpened() => disconnect();

  /// The three steps of coming up, named so the sequence and the checks between
  /// them can be observed. A real LiveKit room cannot be stood up in a unit
  /// test, and the ordering is the part worth testing.
  @protected
  Future<void> connectRoom(String url, String jwt) => room.connect(url, jwt);

  @protected
  Future<void> enableMicrophone(bool on) async => room.localParticipant
      ?.setMicrophoneEnabled(on, audioCaptureOptions: microphone);

  @protected
  Future<void> enableCamera(bool on) async =>
      room.localParticipant?.setCameraEnabled(on);

  Future<void> setMicrophoneEnabled(bool on) => enableMicrophone(on);

  Future<void> setCameraEnabled(bool on) => enableCamera(on);

  /// Leaves the SFU and releases the capture devices.
  ///
  /// Never throws: a hangup runs on a path that also has a Matrix membership to
  /// retract and a recording to flush, and a failure to close a socket must not
  /// leave those undone.
  Future<void> disconnect() async {
    _released = true;
    try {
      await room.disconnect();
    } catch (e, s) {
      Logs().w('Disconnecting call media failed', e, s);
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await room.dispose();
  }
}

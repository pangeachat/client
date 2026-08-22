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
  ///
  /// `stopAudioCaptureOnMute` is turned OFF, against the LiveKit default of on.
  /// On the default, muting STOPS the capture track and unmuting builds a brand
  /// new one — and the recorder tap, attached once to the original track, is
  /// left on a dead track, so everything the learner says after they unmute goes
  /// unrecorded. Left running, mute only disables the track: it transmits
  /// silence to the peer and the recorder captures that same silence, so a mute
  /// reads as a pause in the transcript and speech after it is still captured on
  /// the one continuous track. The cost is that the microphone stays claimed
  /// while muted; the recording, which is the point of the call, is what wins.
  static const microphone = AudioCaptureOptions(
    echoCancellation: true,
    noiseSuppression: true,
    stopAudioCaptureOnMute: false,
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

    // The microphone is published before the camera, and that is not a leak,
    // though a first read of it looks like one. This runs on exactly one path —
    // ActiveCall._start, reached only when the user PLACES or ANSWERS a call —
    // so by the time any audio reaches the peer the user has already chosen to
    // be on the call and to be heard. Audio coming up before video, including
    // while a camera permission prompt is still open, is how every calling
    // product connects; the recording also needs the audio track first. A
    // camera that then fails is handled below, and does not take the call
    // with it.
    await enableMicrophone(true);
    if (_released) return _releaseWhatOpened();

    if (!video) return;
    // A call fails only when the CALL cannot happen. No microphone is no
    // call, so that throw stands; a camera that will not open is a degraded
    // call, not a failed one, and letting it throw here tore down a working
    // audio conversation over a blocked camera. Two real ways to hit it:
    // `Permissions-Policy: camera=()` on the web hosts, and a user who denies
    // the camera prompt after accepting the microphone.
    try {
      await enableCamera(true);
    } catch (e, s) {
      _cameraFailed = true;
      Logs().w('The camera would not open; continuing with audio only', e, s);
    }
    if (_released) return _releaseWhatOpened();
  }

  /// Whether the camera refused to open on a call that asked for video.
  ///
  /// Read by the UI so a video call that came up without a picture can say so
  /// rather than looking like a silent failure.
  bool get cameraFailed => _cameraFailed;
  bool _cameraFailed = false;

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
  // A note on failure, for both of these: livekit_client 2.11.0 creates the
  // capture track and THEN publishes it, and if the publish throws it does not
  // stop the track it just created — nor does room teardown, which only stops
  // PUBLISHED tracks. The created track is never handed back, so there is no
  // handle here to close it either. On a publish failure over an already
  // connected room — rare, since the socket is up by the time these run — the
  // device can stay claimed. This is upstream (the same on the SDK's main
  // branch); closing it from here would mean publishing the track by hand
  // instead of through these one-liners, which is not warranted for a failure
  // this narrow. Recorded so it is a known limitation, not a surprise.
  @protected
  Future<void> enableMicrophone(bool on) async => room.localParticipant
      ?.setMicrophoneEnabled(on, audioCaptureOptions: microphone);

  @protected
  Future<void> enableCamera(bool on) async =>
      room.localParticipant?.setCameraEnabled(on);

  Future<void> setMicrophoneEnabled(bool on) =>
      _setCapture(enableMicrophone, on);

  Future<void> setCameraEnabled(bool on) => _setCapture(enableCamera, on);

  /// Turns a capture device on or off during a call, on the same terms coming
  /// up uses.
  ///
  /// Turning something ON opens a device, so it obeys exactly the rule
  /// [connect] does: refuse once the call has been released, and reconcile
  /// afterwards — because a hangup landing while the enable is in flight cannot
  /// stop it, and a microphone re-opened after teardown is the precise leak the
  /// checks in [connect] exist to prevent. Unmuting into a call that has just
  /// ended is the ordinary way this happens: the user taps unmute at the same
  /// moment the other side hangs up.
  ///
  /// Turning OFF only releases a device, so it is always safe and never guarded
  /// — muting a call that has already ended is a no-op, not a leak.
  Future<void> _setCapture(Future<void> Function(bool) enable, bool on) async {
    if (!on) return enable(false);
    if (_released) return;
    await enable(true);
    if (_released) return _releaseWhatOpened();
  }

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

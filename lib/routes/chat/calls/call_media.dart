import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart';
import 'package:matrix/matrix.dart' show Logs;

import 'package:fluffychat/routes/chat/calls/call_roster.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

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

  /// This device's wall clock.
  ///
  /// Injected for the same reason `CallCaptureService` injects one: what reads
  /// it exists to survive a clock that disagrees with another device's, and
  /// that disagreement is not reachable from a test any other way.
  final DateTime Function() now;

  CallMedia({Room? room, DateTime Function()? now})
    : room = room ?? Room(),
      now = now ?? DateTime.now;

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

  /// Announced the instant the microphone is publishing, from inside [connect].
  ///
  /// The microphone is the one step of coming up that asks the PLATFORM for
  /// something — the permission dialog, when the learner has not answered it
  /// before — and things outside this object wait on that grant. The end of
  /// [connect] is the same fact several steps later: the camera is published in
  /// between, its own dialog can be up in that window, and a learner who leaves
  /// the app during either one is already gone by the time [connect] returns.
  /// Whatever has to act while the grant is fresh listens here instead.
  ///
  /// Announced once per call, from the coming-up path, and deliberately NOT
  /// from [enableMicrophone], which every unmute also goes through: a grant is
  /// something that happens once, not something to re-announce per publish.
  void Function()? onMicrophoneLive;

  /// Connects to the SFU and publishes this device's media.
  ///
  /// Audio is published before video and awaited, so a caller can start
  /// recording the moment this returns rather than polling for a track that
  /// may still be negotiating.
  /// Connecting is several round-trips, and a hangup can land inside any of
  /// them. Each step checks first, so a call the user abandoned never ends up
  /// opening a microphone or a camera after teardown has run.
  ///
  /// COMING UP IS ALL OR NOTHING once the socket is up. A step that THROWS is
  /// the same shape of leak as a step that was abandoned, and it was left to
  /// the caller: the microphone is a required step by design — no microphone is
  /// no call — so its throw used to leave this device sitting in the SFU, with
  /// the peer seeing a participant who publishes nothing.
  ///
  /// WHAT THE RELEASE COVERS IS NARROWER THAN IT LOOKS, and saying so is the
  /// point of this paragraph. [_releaseWhatOpened] is `disconnect()`, which
  /// gives back the socket and the tracks that were PUBLISHED over it — never a
  /// capture track the SDK created and then failed to publish, which this
  /// object is never handed and so could not close. The capture device is
  /// nonetheless returned on the one path that reaches this catch, because the
  /// SDK returns it rather than because anything here does: the microphone is
  /// the only step whose throw arrives here at all — a camera failure is caught
  /// inside [_publish] and a missing participant never throws — and the audio
  /// half of the note above [enableMicrophone] is the half that cleans up.
  Future<void> connect(CallToken grant, {required bool video}) async {
    if (_released) return;
    await connectRoom(grant.url, grant.jwt);
    if (_released) return _releaseWhatOpened();

    try {
      await _publish(video: video);
    } catch (_) {
      // Released here rather than at the call site. `ActiveCall` does tear a
      // failed start down today, so this is this object's own invariant rather
      // than a leak it can see — and an invariant the next caller cannot
      // forget. The throw itself is untouched: the caller still learns the call
      // failed, and still learns why.
      await _releaseWhatOpened();
      rethrow;
    }
  }

  /// The publishing half of coming up.
  ///
  /// Split out so the release above covers EVERY step of it, including any
  /// added later — which is precisely how this class of bug recurs: the camera
  /// step remembered to handle its own failure and the microphone step did not.
  Future<void> _publish({required bool video}) async {
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
    // AFTER the release check, never before it: a call the user abandoned while
    // the microphone was opening is on its way down, and announcing a live
    // microphone into that would have listeners acting on a call that no longer
    // exists.
    _announceMicrophone();

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

  /// Tells the listener the microphone is live, and refuses to let that cost
  /// the call.
  ///
  /// A listener throwing here would arrive at [connect] as the MICROPHONE step
  /// failing, which is the one failure coming up treats as fatal — so a bug in
  /// something merely watching the grant would tear down a call whose audio was
  /// up and working, and the log would blame the microphone. What listens to
  /// this is the call's survival in the background, never its existence.
  void _announceMicrophone() {
    try {
      onMicrophoneLive?.call();
    } catch (e, s) {
      Logs().w('A listener on the live microphone threw', e, s);
    }
  }

  /// Releases what coming up had already opened, whether a step finished after
  /// teardown had run or a step failed outright.
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

  // A note on a publish that fails, for both of these. Read off the pinned
  // livekit_client 2.11.0 rather than carried forward, because the two halves
  // no longer behave the same and an answer good for one is wrong for the
  // other. `setSourceEnabled` CREATES the capture track — the device is claimed
  // at that moment — and only then publishes it, so a publish that throws is a
  // moment where a device is open and unpublished. Room teardown does not reach
  // one: `Room._cleanUp` calls `unpublishAllTracks`, which walks the
  // participant's PUBLISHED tracks and nothing else, and the created track is
  // never returned to us either.
  //
  // AUDIO is given back, by the SDK. `_publishAudioTrack` takes
  // `shouldStopOnFailure = !track.isActive` before it starts the track — true
  // for one `LocalAudioTrack.create` has just built, since `Track.start` is the
  // only thing that sets that flag and `create` never calls it — and its own
  // catch stops the track before rethrowing, which releases the microphone. So
  // a microphone that fails to publish does NOT stay claimed, and [connect]
  // saying a failed join leaves nothing behind is true.
  //
  // VIDEO is not. `_publishVideoTrack` has no equivalent catch, so a camera
  // that fails to publish stays claimed for the rest of the call and past
  // teardown — with the indicator light on, which is how a learner would first
  // notice. Still upstream, and still narrow. Closing it here would mean
  // creating and publishing the camera track by hand instead of through this
  // one-liner, which also rewrites the mid-call unmute path that shares it, and
  // nothing in this suite can reach a real publish to prove either. Recorded as
  // the known limitation it is rather than fixed blind.
  @protected
  Future<void> enableMicrophone(bool on) async => (await _publishingAs(
    on,
  ))?.setMicrophoneEnabled(on, audioCaptureOptions: microphone);

  @protected
  Future<void> enableCamera(bool on) async =>
      (await _publishingAs(on))?.setCameraEnabled(on);

  /// The participant a capture change acts through, or null when there is
  /// nothing to act on and that is fine.
  ///
  /// Turning a device ON must PROVE it had something to turn on: `?.` on a
  /// missing local participant returned as though the microphone had been
  /// published when nothing had, and the call went on to connect and ring
  /// with this side unable to be heard. Turning one OFF may find nothing --
  /// muting a call that has already ended releases a device that is already
  /// released, which is a no-op, not a failure.
  Future<LocalParticipant?> _publishingAs(bool on) async {
    final ready = room.localParticipant;
    if (ready != null) return _anchored(ready);
    if (!on) return null;
    // Waited for, briefly, before being called a failure. The participant
    // appears as part of connecting, and asking a beat too early is a race
    // rather than an error -- turning that race into a throw failed whole
    // calls that were coming up perfectly well. A participant that never
    // arrives is still a failure, and still says so.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (_released) return null;
      final late = room.localParticipant;
      if (late != null) return _anchored(late);
    }
    // Loud, but not fatal. The silent `?.` this replaced was wrong because it
    // reported success for a step that never happened; throwing instead was
    // wrong in the other direction, and the browser suite proved it within
    // the hour -- three scenarios where answering published no membership,
    // because a failure here aborts the connect before the room is ever told
    // we joined. A call nobody can hear is bad; a call that refuses to exist
    // is worse, and the flag lets the UI say which one this is.
    Logs().w('No local participant to publish through; nothing was opened');
    _captureRefused = true;
    return null;
  }

  /// Reads both clocks the first time this call has a participant to read them
  /// from, and hands the participant straight back.
  ///
  /// Latched, not re-read. The two readings describe this device's clock
  /// against the SFU's, which is a property of the CLOCKS and not of the
  /// moment, so one measurement stands for the call — and `joinedAt` is fixed
  /// at join anyway, so a later device reading beside it would measure the
  /// call's own duration rather than any disagreement. It sits on this path
  /// because this is where the local participant is first known to exist:
  /// [connect] publishes the microphone through it before any audio is
  /// captured, and the later mute and camera calls that also come through here
  /// find the latch already taken.
  LocalParticipant _anchored(LocalParticipant participant) {
    // Stamped by the SFU, so both devices in the call read the SAME clock
    // here. Whole SECONDS: the millisecond field exists in the protocol and
    // livekit_client 2.11.0 keeps it behind a private member, so the offset
    // this yields is good to about a second. That is the documented limit of
    // the correction, and it is two orders of magnitude better than the skew
    // it exists to remove.
    //
    // `joinedAt` falls back to this device's own clock when the participant
    // carries no server info, which would read as two clocks in perfect
    // agreement. Unreachable in practice: livekit_client only ever builds a
    // local participant through `createFromInfo`, which sets that info before
    // the object exists. Named because it is an upstream property this
    // correction leans on, not one this code can enforce.
    anchorClocksTo(participant.joinedAt);
    return participant;
  }

  /// Takes both clock readings, once, against the SFU's stamp for this join.
  ///
  /// ONE argument, deliberately. The device's own clock is read INSIDE this
  /// method rather than handed to it, so the two readings cannot be passed the
  /// wrong way round at the call site — a swap there would report the offset
  /// negated, which doubles the skew instead of removing it. It also puts the
  /// whole rule under test: a LiveKit connection cannot be stood up in a unit
  /// test, so anything left inside [_anchored] is only reachable from a real
  /// call, and what is left there now is one expression.
  ///
  /// KNOWN LIMIT: the device clock is read HERE, at join, while every position
  /// this half carries is stamped from a base the capture service reads at the
  /// FIRST AUDIO of the call. Both are the same clock, so the offset applies —
  /// unless that clock is corrected in between, in which case the offset
  /// describes the clock the positions are not on. Seconds apart in practice,
  /// and the alternative is worse: `joinedAt` is fixed at join, so pairing it
  /// with a later device reading would measure the call's own length instead.
  @visibleForTesting
  void anchorClocksTo(DateTime sfuJoinedAt) {
    _clockAnchor ??= ClockAnchor.of(
      sfuMs: sfuJoinedAt.millisecondsSinceEpoch,
      // The same wall clock every position in this half is stamped from, read
      // as close to the SFU's own instant as this device can observe it. What
      // separates them is the join response's flight time -- tens of
      // milliseconds, inside the second of quantisation above.
      deviceMs: now().millisecondsSinceEpoch,
    );
  }

  /// Where this device's wall clock sat relative to the SFU's, or null when a
  /// usable pair of readings was never taken.
  ///
  /// Read by the transcript writer at the END of the call, off this latch,
  /// rather than measured there: by then `joinedAt` is minutes in the past and
  /// the device clock has moved with the call.
  ///
  /// Null is a real answer and must stay one. The reader refuses to correct
  /// ANY half of a transcript unless every half that carries words has an
  /// offset, so a missing one costs the correction and never a word.
  ClockAnchor? get clockAnchor => _clockAnchor;
  ClockAnchor? _clockAnchor;

  /// Whether a capture device could not be opened because there was nothing
  /// to open it through. Read by the UI so a call with no microphone says so.
  bool get captureRefused => _captureRefused;
  bool _captureRefused = false;

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
  ///
  /// What it does NOT borrow from [connect] is the all-or-nothing release on a
  /// failure, and the difference is what the connection means at each point. In
  /// [connect] the room is up for a call that has not started, so a required
  /// step failing means there is no call to hold it open for. Here the call is
  /// live and two people are talking: an unmute the platform refuses costs the
  /// microphone, and tearing the conversation down over it would be the same
  /// mistake the camera arm above exists to avoid.
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

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart';
import 'package:matrix/matrix.dart' show Logs;

import 'package:fluffychat/routes/chat/calls/call_roster.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/sfu_join_stamp.dart';
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

  /// [watchJoinStamp] is the real subscription unless a test replaces it.
  ///
  /// Injected for one reason: a join response cannot be delivered through a
  /// real `Room` in a unit test — emitting on its signal emitter wakes
  /// livekit_client's own handler, which reaches a platform channel. Without a
  /// seam here, the only thing a test could reach is [anchorClocksTo] called by
  /// hand, which proves a reading is consumed and says nothing about WHICH
  /// callback this object hands over. That gap let a regression through twice:
  /// a version that stored the stamps and paired them with a later clock
  /// reading passed every test in this file.
  ///
  /// [watchParticipantStamps] is the real subscription unless a test replaces
  /// it, for the same reason and with the same gap: neither of the two signal
  /// frames it reads can be delivered through a real `Room` here.
  CallMedia({
    Room? room,
    DateTime Function()? now,
    JoinStampWatch? watchJoinStamp,
    ParticipantStampWatch? watchParticipantStamps,
  }) : room = room ?? Room(),
       now = now ?? DateTime.now {
    // Attached HERE, in the constructor, and not on the connect path. The join
    // response is delivered and consumed inside `Room.connect`, so a
    // subscription opened once that returns has already missed the only frame
    // the readings arrive in. Putting it before the connect worked and was one
    // edit away from not working: nothing about `connectRoom` made the order
    // load-bearing, and nothing failed when it was reversed. From the
    // constructor there is no order left to get wrong, because there is no
    // other path.
    //
    // [anchorClocksTo] rather than a closure that stores the reading: it reads
    // the device clock ITSELF, so no window is opened HERE between being told
    // about the join and pairing the two halves. That is all this line can
    // claim. The delay before it -- livekit_client's async delivery of the
    // event -- is not ours to close, and is described on [anchorClocksTo].
    _stopJoinStampWatch = (watchJoinStamp ?? watchSfuJoinStamp)(
      this.room,
      anchorClocksTo,
    );
    // The second watch, attached here for the reason above and one more of its
    // own: the join response names every device ALREADY in the room, and it is
    // the only frame GUARANTEED to name them -- a later update names one only
    // when its state changes, which nothing here controls. A subscription
    // opened after the connect would still catch every later join and might
    // never hear of the devices that were there first.
    //
    // [recordJoinStamps] rather than [anchorClocksTo]. These are statements
    // about the SFU's clock alone; nothing on this path reads a device clock,
    // and nothing on it may begin to, because a participant update restates a
    // join from some earlier moment and a pair built here would measure the
    // time since that join. [watchSfuParticipantStamps] is deliberately a
    // different function from the one above so that no edit here can reach the
    // anchor.
    _stopParticipantStampWatch =
        (watchParticipantStamps ?? watchSfuParticipantStamps)(
          this.room,
          recordJoinStamps,
        );
  }

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
  ///
  /// [metadataGrant] is passed through rather than read here: it is a fact about
  /// the TOKEN, which the caller holds and this object only dials with. It
  /// defaults to unknown so a caller with no token to hand — every test that
  /// does not care — is not made to state one.
  CallRoster roster({
    required String myUserId,
    MetadataGrant metadataGrant = MetadataGrant.unknown,
  }) =>
      CallRoster(room: room, myUserId: myUserId, metadataGrant: metadataGrant);

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
    final microphoneLive = await enableMicrophone(true);
    if (_released) return _releaseWhatOpened();
    // AFTER the release check, never before it: a call the user abandoned while
    // the microphone was opening is on its way down, and announcing a live
    // microphone into that would have listeners acting on a call that no longer
    // exists.
    //
    // And only when a microphone actually opened. The step RETURNING is a
    // different fact: with no local participant to publish through it comes
    // back having opened nothing at all (see [_publishingAs]), and announcing
    // off the return alone told the listener a permission had been granted
    // that had not been asked for. What listens spends a one-per-call budget
    // on the news, so a false grant does not merely mislead — it consumes the
    // retry the real grant would have had.
    if (microphoneLive) _announceMicrophone();

    if (!video) return;
    // A call fails only when the CALL cannot happen. No microphone is no
    // call, so that throw stands; a camera that will not open is a degraded
    // call, not a failed one, and letting it throw here tore down a working
    // audio conversation over a blocked camera. Two real ways to hit it:
    // `Permissions-Policy: camera=()` on the web hosts, and a user who denies
    // the camera prompt after accepting the microphone.
    try {
      // The same rule as the microphone above, at the other site that reports
      // a capture step's outcome. A camera that quietly published nothing is a
      // video call with no picture exactly as much as one that threw is, and
      // reading only the throw left the screen showing a camera control for a
      // camera that had never come on.
      if (!await enableCamera(true)) _cameraFailed = true;
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

  CancelListenFunc? _stopJoinStampWatch;
  CancelListenFunc? _stopParticipantStampWatch;

  /// The SFU's join stamps for one participant, or null when nothing in this
  /// call has named them.
  ///
  /// Keyed by the identity the SFU used, which is the string the token service
  /// builds out of the account and the device — the same one `CallParticipant`
  /// parses a device id back out of.
  ///
  /// RAW, both halves, exactly as the frame carried them. Zero means the server
  /// said nothing: `joined_at_ms` has only been sent since livekit-server
  /// v1.8.4, so a stamp with no millisecond half is an ordinary answer from an
  /// older SFU rather than a fault, and what to make of it is the reader's. The
  /// coarse half travels beside it so a reader can tell a refinement from a
  /// contradiction without a second source, which is the check
  /// [anchorClocksTo] already makes for this device's own pair.
  ///
  /// Exposed so a comparison between two devices' joins can be made at the
  /// resolution the wire actually carries. `CaptureElection` reads it for
  /// exactly that, and DESTROYS captured audio on the answer, so what is handed
  /// over has to stay raw: the reader decides, per PAIR, whether both halves
  /// are millisecond-real, and a store that had already repaired one would have
  /// taken that decision away from it.
  ({int secondsMs, int ms})? sfuJoinStampsFor(String identity) {
    final held = _sfuJoinStamps[identity];
    return held == null ? null : (secondsMs: held.secondsMs, ms: held.ms);
  }

  /// The latest CURRENT statement about each identity, plus the session and
  /// version that decide what "current" means.
  ///
  /// [sfuJoinStampsFor] hands out only the two time halves, because that is all
  /// the election orders on; the `sid` and `version` beside them never leave
  /// this object. They are here so [recordJoinStamps] can refuse a statement
  /// the wire itself says is superseded — a departed session's, or an
  /// out-of-order one — rather than letting it overwrite the join a live device
  /// actually holds.
  final Map<String, ({int secondsMs, int ms, String sid, int version})>
  _sfuJoinStamps = {};

  /// Records what the SFU last said about each participant a frame named — but
  /// only the statements the wire itself has not already superseded.
  ///
  /// THE LATEST CURRENT STATEMENT WINS, which is nearly but not quite "the
  /// latest statement wins", and the gap is where audio was being destroyed.
  /// The election reads this store to order two devices' joins and DISCARDS a
  /// learner's captured audio when a sibling's join sorts first. A learner's
  /// device can leave a call and rejoin it under the SAME identity: the rejoin
  /// takes a later join instant and a fresh `sid`, and the earlier session's
  /// updates — its `DISCONNECTED` notice above all — can still be in flight.
  /// Stored blindly, a delayed statement from the session that ENDED overwrites
  /// the join the device currently holds with the earlier one, and the election
  /// then reads the live device as having been in the room before a sibling it
  /// in fact joined after, and throws away the sibling's tail. That tail is the
  /// only copy; no later election brings it back.
  ///
  /// Only a statement describing the SAME live session or a NEWER one may move
  /// the held join. An older session's late word — whatever sid it carries —
  /// cannot, because moving the store back to an earlier join is what lets the
  /// election read a live device as present before a sibling it in fact joined
  /// after, and throw away the sibling's only copy of the tail:
  ///
  ///   - A participant the SFU marks DISCONNECTED has LEFT. livekit_client drops
  ///     it rather than updating it (room.dart:798 `continue`s on that state),
  ///     and a departed session's statement must never move a live device's
  ///     join here either. A `hasLeft` frame never writes, so the last CURRENT
  ///     join stands.
  ///
  ///   - A statement for the SAME `sid` is the same session; it may write only
  ///     if its `version` is not behind what is held. livekit_client refuses a
  ///     lower version on a held session (participant.dart:221) and this refuses
  ///     it on the same terms, so a reordered frame cannot walk the store back.
  ///
  ///   - A DIFFERENT `sid` is a different session under one identity — a
  ///     leave-and-rejoin. Only a STRICTLY LATER join is a newer session; the
  ///     SFU stamps each join from its own monotonic clock, so a rejoin always
  ///     lands after the session it replaced. An equal or earlier join under a
  ///     different sid is an older session's delayed statement — the gap the
  ///     same-sid version check could not close, because a fresh sid restarts
  ///     the counter — and it is kept out here rather than left to overwrite the
  ///     rejoin the device actually holds.
  ///
  /// What is NOT judged here is whether the numbers are believable times — a
  /// zero millisecond half, a stamp past the clock ceiling. That stays the
  /// reader's, because the reader decides it per PAIR; this only keeps the store
  /// to the statement the wire says is current.
  @visibleForTesting
  void recordJoinStamps(List<SfuParticipantStamps> stamps) {
    for (final stamp in stamps) {
      // A device that has left is not describing the join a live device holds.
      // Never let its statement overwrite one.
      if (stamp.hasLeft) continue;
      final held = _sfuJoinStamps[stamp.identity];
      if (held != null && !_supersedesHeldJoin(stamp, held)) continue;
      _sfuJoinStamps[stamp.identity] = (
        secondsMs: stamp.secondsMs,
        ms: stamp.ms,
        sid: stamp.sid,
        version: stamp.version,
      );
    }
  }

  /// Whether [stamp] describes the same live session already held for its
  /// identity, or a newer one — the only statements allowed to move the join.
  ///
  /// Same session (same `sid`): ordered by the SFU's own monotonic `version`, so
  /// a frame at or past the held version is the same join restated or a fresher
  /// statement of it, and a lower one is reordered and refused. Different
  /// session (different `sid`): ordered by the join instant, so only a strictly
  /// later join — a genuine rejoin — supersedes, and an older session's late
  /// statement cannot drag the store back to an earlier join.
  static bool _supersedesHeldJoin(
    SfuParticipantStamps stamp,
    ({int secondsMs, int ms, String sid, int version}) held,
  ) => stamp.sid == held.sid
      ? stamp.version >= held.version
      : _joinInstant(stamp.secondsMs, stamp.ms) >
            _joinInstant(held.secondsMs, held.ms);

  /// A join collapsed to one comparable instant, so two SESSIONS of one identity
  /// can be ordered against each other. The millisecond reading when it refines
  /// the coarse one, else the coarse second — the same rule the anchor reads by.
  /// This orders which SESSION is newer, a coarser question than the per-pair
  /// resolution the election discards on, so a mixed pair needs no special case.
  static int _joinInstant(int secondsMs, int ms) =>
      ClockAnchor.millisecondRefinement(secondsMs, ms) ?? secondsMs;

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
  // Both of these answer whether the change reached a real PUBLICATION, which
  // is the only proof the device did anything. Returning was taken for that
  // proof and is not: the `?.` these used to end in came back indistinguishable
  // from success when there was no participant to publish through, and every
  // reader downstream — the grant announcement, the camera-failed flag — was
  // reading a step's return where it needed a step's effect.
  //
  // The publication is the SDK's own answer rather than an inference of ours.
  // On the pinned livekit_client 2.11.0, `setSourceEnabled` turning a source ON
  // either hands back the publication it made or throws (local.dart:815-825),
  // so a null is that library saying it published nothing.
  @protected
  Future<bool> enableMicrophone(bool on) async {
    final participant = await _publishingAs(on);
    if (participant == null) return false;
    final published = await participant.setMicrophoneEnabled(
      on,
      audioCaptureOptions: microphone,
    );
    return published != null;
  }

  @protected
  Future<bool> enableCamera(bool on) async {
    final participant = await _publishingAs(on);
    if (participant == null) return false;
    return await participant.setCameraEnabled(on) != null;
  }

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
    if (ready != null) return ready;
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
      if (late != null) return late;
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

  /// Takes both halves of the anchor, once, from one join response.
  ///
  /// ONE OBSERVATION OR NONE, which is the rule this method exists to keep.
  /// An anchor is a PAIR and only its DIFFERENCE means anything, so the two
  /// halves have to describe the same instant.
  ///
  /// WHAT IS ACTUALLY GUARANTEED IS NARROWER THAN THAT, and the difference is
  /// worth stating because it is the remaining error in the whole correction.
  /// The device clock is read the moment this APP IS TOLD about the join
  /// response, not the moment the frame arrived. livekit_client delivers
  /// `SignalJoinResponseEvent` over an async broadcast stream
  /// (`StreamController.broadcast(sync: false)`), so this runs in a later
  /// event-loop turn than the socket read. Ordinarily that is the very next
  /// turn and the gap does not show: a probe against a local SFU measured 7ms
  /// end to end, server stamp to device reading. But NOTHING BOUNDS IT. An
  /// isolate stalled by a long frame, a GC pause, or a suspended app delivers
  /// the same event late, and every millisecond of that lag is added to the
  /// offset as though it were clock skew — a five-second stall records a
  /// five-second disagreement between two clocks that agree perfectly.
  ///
  /// Not detectable from in here, and the reason is the same one that makes the
  /// anchor necessary: `deviceMs - sfuMs` is the skew and the lag added
  /// together, and one observation cannot separate them. Catching it would take
  /// an INDEPENDENT measurement — the cheapest being an event-loop lag probe, a
  /// periodic timer compared against its own nominal interval, running for the
  /// life of the call — plus a lateness threshold nobody here has data to set.
  /// It would buy refusing a contaminated anchor; it would cost a timer per
  /// call and false refusals on a device that merely paused at the wrong
  /// moment, each one costing the correction. Left unbuilt rather than built on
  /// a guess.
  ///
  /// ANYONE SIZING FURTHER WORK ON THIS SHOULD START HERE. That delivery lag is
  /// now the LARGEST error term in the offset, and the only unbounded one — it
  /// is bigger than the second-versus-millisecond resolution this whole
  /// mechanism was built to fix. Reading proto field 17 removed up to a second;
  /// a stalled isolate can put back more than that and nothing here would know.
  /// Chasing finer readings from the SFU is polishing the smaller term. The
  /// next real improvement is either bounding this one or taking a second
  /// observation later in the call and comparing, which would catch a
  /// contaminated first reading without a threshold anybody had to guess.
  ///
  /// There is deliberately NO other way in. An earlier version fell back to
  /// pairing the participant's stamp with this device's clock read after
  /// `Room.connect` returned, and that pair is not a measurement: it carries
  /// however long the connect took — ICE, DTLS, negotiation — which differs
  /// between two phones by seconds. It produced a confident anchor that ordered
  /// a transcript by connect speed, with no sign to a reader that anything was
  /// wrong. `ClockAnchor` already refuses a reading it cannot vouch for rather
  /// than rescuing it into a wrong one, and this now does the same: a call
  /// whose join response was never seen carries NO anchor. That costs the
  /// correction and never a word — the reader shows every half it has. It does
  /// NOT stop them being interleaved: `clockShiftFor` is zero for every half
  /// when the clocks cannot be reconciled, so they still merge on raw device
  /// clocks and a reply can still render above its question. What is withheld
  /// is the printed TIMES, so at least the wrong order is never dressed up as
  /// a measured one.
  ///
  /// The device clock is read INSIDE this method rather than handed to it, so
  /// the two clocks cannot be passed the wrong way round at the call site — a
  /// swap there would report the offset negated, which doubles the skew instead
  /// of removing it.
  ///
  /// Latched on the FIRST join response. A reconnect restamps the join, and the
  /// offset is a property of the CLOCKS rather than of any one join, so the
  /// earliest self-consistent pair is as good a measurement as a later one.
  ///
  /// KNOWN LIMIT: the device clock is read at JOIN, while every position this
  /// half carries is stamped from a base the capture service reads at the FIRST
  /// AUDIO of the call. Both are the same clock, so the offset applies — unless
  /// that clock is corrected in between, in which case the offset describes the
  /// clock the positions are not on. Seconds apart in practice, and the
  /// alternative is worse: the SFU stamp is fixed at join, so pairing it with a
  /// later device reading would measure the call's own length.
  @visibleForTesting
  void anchorClocksTo(({int secondsMs, int ms}) stamps) {
    _clockAnchor ??= ClockAnchor.of(
      sfuMs: _sfuReading(stamps.secondsMs, stamps.ms),
      deviceMs: now().millisecondsSinceEpoch,
    );
  }

  /// The SFU reading to anchor on: [ms] when it is the same join [seconds]
  /// reports only stated more precisely, and [seconds] whenever it is not.
  ///
  /// A REFINEMENT ONLY, and the rule that keeps it one now lives on
  /// [ClockAnchor.millisecondRefinement] rather than here — because the
  /// recorder election asks the same question of a SIBLING's stamps and answers
  /// it by DESTROYING captured audio. Two copies of that window could drift
  /// apart, and the half that drifted would be the half that deletes speech.
  ///
  /// What stays here is the FALLBACK, which is this caller's alone. A reading
  /// the rule refuses leaves the correction exactly where it was before field
  /// 17 existed, rather than being repaired; [ClockAnchor.of] keeps the last
  /// word on the value that wins, and refuses it outright if it is not a time
  /// at all.
  static int _sfuReading(int seconds, int ms) =>
      ClockAnchor.millisecondRefinement(seconds, ms) ?? seconds;

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

  Future<bool> setMicrophoneEnabled(bool on) =>
      _setCapture(enableMicrophone, on);

  Future<bool> setCameraEnabled(bool on) => _setCapture(enableCamera, on);

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
  /// Answers, like the steps it runs, whether the device is actually publishing
  /// afterwards — so a caller latching anything off a toggle latches it off the
  /// effect rather than off the request. A change refused for a released call,
  /// or released again the moment it took, is not one that happened.
  Future<bool> _setCapture(Future<bool> Function(bool) enable, bool on) async {
    if (!on) return enable(false);
    if (_released) return false;
    final live = await enable(true);
    if (_released) {
      await _releaseWhatOpened();
      return false;
    }
    return live;
  }

  /// Every participant's video in this call, the peer's first and this
  /// device's last -- the order the panel lays out full-bleed then inset.
  ///
  /// One feed per video PUBLICATION, whether its camera is on or off. Switching
  /// a camera off does not remove its publication: [setCameraEnabled] mutes it
  /// and leaves the last frame attached rather than unpublishing, so a renderer
  /// left pointing at a muted track freezes on that frame and repaints black
  /// once the view is torn down and rebuilt. The feed carries
  /// [CallVideoFeed.cameraOff] so a view drops the renderer and shows the
  /// participant's avatar in that tile's place instead (#8795) -- for the peer
  /// and for this device alike.
  List<CallVideoFeed> videoFeeds() {
    final local = room.localParticipant;
    return [
      for (final participant in room.remoteParticipants.values)
        for (final publication in participant.videoTrackPublications)
          CallVideoFeed.of(
            track: publication.track,
            muted: publication.muted,
            isLocal: false,
          ),
      if (local != null)
        for (final publication in local.videoTrackPublications)
          CallVideoFeed.of(
            track: publication.track,
            muted: publication.muted,
            isLocal: true,
          ),
    ];
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
    // Tidiness rather than a leak fix, and cheap enough to state plainly: both
    // subscriptions live on the room's own signal emitter, which the dispose
    // below closes anyway. Cancelling first means teardown does not depend on
    // that being true of a future livekit_client.
    await _stopJoinStampWatch?.call();
    _stopJoinStampWatch = null;
    await _stopParticipantStampWatch?.call();
    _stopParticipantStampWatch = null;
    await room.dispose();
  }
}

/// One participant's video in a call: the track to render while the camera is
/// on, and the fact that it is OFF when it is not.
///
/// A camera turned off stays published and only muted, so its track keeps
/// painting its last frame; [cameraOff] is what tells a view to drop the
/// renderer and show the participant's avatar instead. Shared by the call
/// panel's peer and self tiles, and by the camera-held-closed path (#8446),
/// so the "camera off shows the avatar" rule lives in one place.
class CallVideoFeed {
  /// The published video track, or null when the publication has none yet.
  final VideoTrack? track;

  /// Whether the camera behind this feed is off -- a view shows the avatar
  /// rather than [track] when this is true.
  final bool cameraOff;

  /// Whether this is THIS device's own camera (the self-view) rather than the
  /// peer's, so a view knows which avatar to fall back to.
  final bool isLocal;

  const CallVideoFeed({
    required this.track,
    required this.cameraOff,
    required this.isLocal,
  });

  /// Builds a feed from a publication's [track] and [muted] flag, deciding
  /// [cameraOff] through [cameraIsOff] so the rule is stated once.
  factory CallVideoFeed.of({
    required VideoTrack? track,
    required bool muted,
    required bool isLocal,
  }) => CallVideoFeed(
    track: track,
    cameraOff: cameraIsOff(muted: muted, hasTrack: track != null),
    isLocal: isLocal,
  );

  /// Whether a camera should be treated as OFF -- shown as an avatar rather
  /// than a live renderer. Off when the publication is MUTED (the camera was
  /// switched off, its last frame lingering for a renderer to freeze on) or
  /// when it has no track. This is the signal LiveKit itself exposes for a
  /// camera being off, and it is what the reported bug turns on: switching a
  /// camera off mutes its publication.
  ///
  /// It is deliberately NOT keyed on the track's liveness. `Track.isActive`
  /// would seem to catch a stopped track, but it is wrong in both directions on
  /// the pinned livekit_client 2.11: a freshly SUBSCRIBED remote camera is
  /// still inactive when its `TrackSubscribedEvent` fires (`start()` is awaited
  /// after), so gating on it flashes the avatar over a live peer; and a track
  /// that ENDS keeps `isActive` true (its `onEnded` only emits an event). The
  /// one true "ended" signal, `TrackEndedEvent`, is `@internal` and unexported,
  /// so an ended-but-unmuted track cannot be distinguished here at all. That
  /// residual case -- rare, e.g. a camera unplugged mid-call without a mute --
  /// is an SDK limitation, not something a wrong liveness guess should paper
  /// over. Pure, so the rule is tested without a LiveKit room.
  static bool cameraIsOff({required bool muted, required bool hasTrack}) =>
      muted || !hasTrack;
}

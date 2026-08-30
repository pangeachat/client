import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';

/// Records what actually reached the SFU layer, so a step that runs after
/// teardown is visible rather than merely improbable.
class RecordingMedia extends CallMedia {
  final List<String> steps = [];
  bool releaseDuringConnect = false;
  bool releaseDuringMic = false;
  bool releaseDuringCamera = false;
  bool cameraThrows = false;
  bool micThrows = false;

  /// A step that returns without having published anything, which is what the
  /// real one does when there is no local participant to publish through. Not
  /// the same as a step that throws, and the difference is the whole point:
  /// this one looks exactly like success from the outside.
  bool micOpensNothing = false;
  bool cameraOpensNothing = false;
  int disconnects = 0;

  @override
  Future<void> connectRoom(String url, String jwt) async {
    steps.add('connect');
    if (releaseDuringConnect) await disconnect();
  }

  @override
  Future<bool> enableMicrophone(bool on) async {
    steps.add('mic:$on');
    if (micThrows) throw StateError('the microphone would not publish');
    if (releaseDuringMic) {
      releaseDuringMic = false;
      await disconnect();
    }
    return !micOpensNothing;
  }

  @override
  Future<bool> enableCamera(bool on) async {
    steps.add('camera:$on');
    if (cameraThrows) throw StateError('camera blocked by policy');
    if (releaseDuringCamera) {
      releaseDuringCamera = false;
      await disconnect();
    }
    return !cameraOpensNothing;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    steps.add('disconnect');
    await super.disconnect();
  }
}

/// Calls the REAL capture steps, so the guard that decides whether a step
/// silently did nothing is the thing under test. An unconnected LiveKit room
/// has no local participant, which is exactly the state being guarded.
class RealSteps extends CallMedia {
  RealSteps({super.now});

  Future<bool> mic(bool on) => enableMicrophone(on);
  Future<bool> cam(bool on) => enableCamera(on);
}

/// Comes up without a socket but with the REAL capture steps, so what the
/// announcement and the camera flag read is what the real guard produces. An
/// unconnected LiveKit room has no local participant, so both steps here return
/// having published nothing — the state that used to be indistinguishable from
/// success.
class RealStepsComingUp extends CallMedia {
  final List<String> steps = [];

  @override
  Future<void> connectRoom(String url, String jwt) async =>
      steps.add('connect');

  @override
  Future<void> disconnect() async {
    steps.add('disconnect');
    await super.disconnect();
  }
}

void main() {
  const grant = CallToken(jwt: 'jwt', url: 'ws://sfu');

  test('connects, then publishes audio, then video', () async {
    final media = RecordingMedia();
    await media.connect(grant, video: true);
    expect(media.steps, ['connect', 'mic:true', 'camera:true']);
  });

  // `Permissions-Policy: camera=()` on the web hosts, or a denied camera
  // prompt, must cost the picture and nothing else. Letting the throw out of
  // connect() tore down a working audio call.
  test(
    'a camera that will not open leaves the call up, audio and all',
    () async {
      final media = RecordingMedia()..cameraThrows = true;
      await media.connect(grant, video: true);
      expect(media.steps, ['connect', 'mic:true', 'camera:true']);
      expect(media.disconnects, 0, reason: 'the call must not be torn down');
      expect(
        media.cameraFailed,
        isTrue,
        reason: 'the UI has to be able to say so',
      );
    },
  );

  // The other half of the same rule. A camera that will not open is a degraded
  // call; a microphone that will not open is no call at all -- so that throw
  // stands, and what must not stand with it is the SFU connection the failed
  // step was reached through. Left up, the peer sees a participant who
  // publishes nothing, and nothing inside this object is left to close it.
  test(
    'a microphone that will not publish takes the connection with it',
    () async {
      final media = RecordingMedia()..micThrows = true;

      await expectLater(
        media.connect(grant, video: true),
        throwsA(isA<StateError>()),
        reason: 'the caller still has to learn the call failed, and why',
      );

      expect(media.steps, ['connect', 'mic:true', 'disconnect']);
      expect(
        media.disconnects,
        1,
        reason: 'a failed join must not leave this device in the SFU',
      );
      expect(
        media.steps,
        isNot(contains('camera:true')),
        reason: 'and nothing further is opened',
      );
    },
  );

  group('announcing that the microphone is live', () {
    // The permission the ongoing-call service waits for is granted at the
    // MICROPHONE, and whoever is waiting on it has to hear so there and not one
    // step later: the camera is published in between -- a second dialog on a
    // video call -- and the learner can leave the app during any of it.
    test('is announced at the microphone, before the camera opens', () async {
      final media = RecordingMedia();
      media.onMicrophoneLive = () => media.steps.add('mic-live');

      await media.connect(grant, video: true);

      expect(media.steps, ['connect', 'mic:true', 'mic-live', 'camera:true']);
    });

    test('is announced on a voice call too', () async {
      // Nothing about the grant is video's: a voice call publishes no camera
      // and its service needs the same permission.
      final media = RecordingMedia();
      media.onMicrophoneLive = () => media.steps.add('mic-live');

      await media.connect(grant, video: false);

      expect(media.steps, ['connect', 'mic:true', 'mic-live']);
    });

    test('a microphone that never opened announces nothing', () async {
      // There is no grant to report: the step threw, the connection is being
      // given back, and a listener told the microphone was live would act on a
      // call that is already failing.
      final media = RecordingMedia()..micThrows = true;
      media.onMicrophoneLive = () => media.steps.add('mic-live');

      await expectLater(
        media.connect(grant, video: true),
        throwsA(isA<StateError>()),
      );

      expect(media.steps, isNot(contains('mic-live')));
    });

    test('a hangup landing WHILE it opens announces nothing', () async {
      // The microphone did open -- the check before the step cannot stop one
      // already in flight -- and it is being released again. Announcing here
      // would hand a live microphone to a listener at the moment the call it
      // belongs to is coming down.
      final media = RecordingMedia()..releaseDuringMic = true;
      media.onMicrophoneLive = () => media.steps.add('mic-live');

      await media.connect(grant, video: true);

      expect(media.steps, isNot(contains('mic-live')));
    });

    test('a microphone that opened NOTHING announces nothing', () async {
      // The failure this covers looks nothing like the throw above: the step
      // returns perfectly normally, having found no participant to publish
      // through and opened no device. Announced off the return alone, the
      // listener is told a permission was granted that was never asked for --
      // and it spends its one per-call foreground retry on that news, so the
      // call goes into the learner's pocket unprotected AND unheard.
      final media = RecordingMedia()..micOpensNothing = true;
      media.onMicrophoneLive = () => media.steps.add('mic-live');

      await media.connect(grant, video: false);

      expect(media.steps, ['connect', 'mic:true']);
      expect(
        media.steps,
        isNot(contains('mic-live')),
        reason: 'there was no grant: nothing was opened to grant',
      );
    });

    test('and the real guard is what produces that answer', () async {
      // Through the REAL capture step rather than a fake's flag, so the two
      // halves cannot drift: the same state that makes the step refuse -- no
      // local participant -- is the state the announcement must stay silent
      // for. Both facts are asserted together because a call that reports the
      // refusal while still announcing the grant is the exact bug.
      final media = RealStepsComingUp();
      media.onMicrophoneLive = () => media.steps.add('mic-live');

      await media.connect(grant, video: false);

      expect(
        media.captureRefused,
        isTrue,
        reason: 'nothing was opened, and the step says so',
      );
      expect(media.steps, isNot(contains('mic-live')));
    });

    test('a listener that throws costs nothing but its own news', () async {
      // What listens is background survival, not the conversation. Left to
      // propagate, a throw from a watcher would arrive as the MICROPHONE step
      // failing -- the one failure coming up treats as fatal -- and would tear
      // down a call whose audio was up and working.
      final media = RecordingMedia();
      media.onMicrophoneLive = () => throw StateError('a bug in a watcher');

      await expectLater(media.connect(grant, video: true), completes);

      expect(media.steps, ['connect', 'mic:true', 'camera:true']);
      expect(media.disconnects, 0, reason: 'the call must not be torn down');
    });

    test('an unmute mid-call is not a fresh grant', () async {
      // A grant happens once. Announced from the enable itself rather than from
      // coming up, every unmute would re-announce it, and whoever is listening
      // would take an action-per-publish out of a permission that has not
      // changed since the call started.
      final media = RecordingMedia();
      await media.connect(grant, video: false);
      media.onMicrophoneLive = () => media.steps.add('mic-live');

      await media.setMicrophoneEnabled(true);

      expect(media.steps, isNot(contains('mic-live')));
    });
  });

  test('a call whose camera came up reports no camera failure', () async {
    final media = RecordingMedia();
    await media.connect(grant, video: true);
    expect(media.cameraFailed, isFalse);
  });

  test('a camera that opened NOTHING is a camera failure too', () async {
    // The same rule as the microphone announcement, at the other site that
    // reports a capture step's outcome. Read off the throw alone, a camera that
    // quietly published nothing left the screen showing a working camera
    // control for a picture that was never coming -- and the first press turned
    // OFF a camera that had never come on.
    final media = RecordingMedia()..cameraOpensNothing = true;

    await media.connect(grant, video: true);

    expect(media.steps, ['connect', 'mic:true', 'camera:true']);
    expect(
      media.cameraFailed,
      isTrue,
      reason: 'a video call with no picture has to be able to say so',
    );
    expect(media.disconnects, 0, reason: 'and it is still a call');
  });

  // The silent failure this replaces: `room.localParticipant?.setMicrophone`
  // returned as though the microphone had been published when there was no
  // participant to publish through, so the call connected and rang with this
  // side unable to be heard.
  test(
    'turning the microphone on with nothing to publish through says so',
    () async {
      final media = RealSteps();
      final live = await media.mic(true);
      expect(
        media.captureRefused,
        isTrue,
        reason: 'the step did not happen, and silence about that is the bug',
      );
      expect(
        live,
        isFalse,
        reason: 'and it says so to its caller, not only to the UI flag',
      );
    },
  );

  test(
    'turning the camera on with nothing to publish through says so',
    () async {
      final media = RealSteps();
      final live = await media.cam(true);
      expect(media.captureRefused, isTrue);
      expect(live, isFalse);
    },
  );

  // Throwing here was tried and is worse: a failure inside connect() aborts
  // before the room is ever told we joined, so the call never happens at all.
  // The browser suite found it within the hour -- three scenarios in one run
  // where answering published no membership.
  test('and does not take the call down with it', () async {
    await expectLater(RealSteps().mic(true), completes);
  });

  test('turning a device OFF with nothing to release is a no-op', () async {
    await RealSteps().mic(false);
    await RealSteps().cam(false);
  });

  test('a voice call publishes no camera', () async {
    final media = RecordingMedia();
    await media.connect(grant, video: false);
    expect(media.steps, ['connect', 'mic:true']);
  });

  test('a hangup landing mid-connect stops the microphone opening', () async {
    // Connecting is several round-trips and a hangup can land inside any of
    // them. Without a check between steps the call would open a microphone,
    // and a camera, after teardown had already run.
    final media = RecordingMedia()..releaseDuringConnect = true;
    await media.connect(grant, video: true);

    expect(media.steps, ['connect', 'disconnect', 'disconnect']);
    expect(
      media.steps,
      isNot(contains('mic:true')),
      reason: 'a call the user abandoned must not open capture devices',
    );
  });

  test(
    'a hangup landing WHILE the microphone opens still releases it',
    () async {
      // The check before each step cannot stop a step already in flight. The
      // microphone opens anyway, so returning without releasing would leave it
      // open with nothing left to close it.
      final media = RecordingMedia()..releaseDuringMic = true;
      await media.connect(grant, video: true);

      expect(media.steps, ['connect', 'mic:true', 'disconnect', 'disconnect']);
      expect(
        media.steps,
        isNot(contains('camera:true')),
        reason: 'and nothing further is opened',
      );
    },
  );

  test('a hangup landing WHILE the camera opens still releases it', () async {
    final media = RecordingMedia()..releaseDuringCamera = true;
    await media.connect(grant, video: true);

    expect(media.steps.last, 'disconnect');
    expect(media.disconnects, 2, reason: 'the reconcile runs after the step');
  });

  test('connect after release does nothing at all', () async {
    final media = RecordingMedia();
    await media.disconnect();
    media.steps.clear();
    await media.connect(grant, video: true);
    expect(media.steps, isEmpty);
  });

  group('turning a device on mid-call obeys the same rule as coming up', () {
    test('unmuting into a call that has already ended opens nothing', () async {
      // The user taps unmute at the same moment the other side hangs up. The
      // microphone must not come back on for a call that is over — the same
      // leak the checks in connect() exist to prevent, on the toggle path.
      final media = RecordingMedia();
      await media.disconnect();
      media.steps.clear();
      await media.setMicrophoneEnabled(true);
      expect(
        media.steps,
        isNot(contains('mic:true')),
        reason: 'an ended call must not reopen the microphone',
      );
    });

    test('an unmute racing a hangup releases the microphone it opened', () async {
      // The check before cannot stop an enable already in flight. It opens the
      // microphone anyway, so it must reconcile afterwards rather than leave it
      // open with nothing left to close it.
      final media = RecordingMedia()..releaseDuringMic = true;
      await media.setMicrophoneEnabled(true);
      expect(media.steps, ['mic:true', 'disconnect', 'disconnect']);
    });

    test('muting an ended call is a harmless no-op, never guarded', () async {
      // Turning a device OFF only releases it, so it is always allowed — a mute
      // after the call ended must still be attempted, not refused.
      final media = RecordingMedia();
      await media.disconnect();
      media.steps.clear();
      await media.setMicrophoneEnabled(false);
      expect(media.steps, ['mic:false']);
    });
  });

  group('the clock anchor the transcript is corrected by', () {
    // The SFU's stamp for this device's join, and a device clock reading
    // thirty seconds later than it -- a device thirty seconds fast.
    final sfuJoin = DateTime.utc(2026, 8, 26, 9);
    final deviceAtJoin = sfuJoin.add(const Duration(seconds: 30));

    CallMedia mediaAt(DateTime deviceNow) => RealSteps(now: () => deviceNow);

    test('a call that never had a participant carries no anchor', () {
      // The state `RealSteps` is in: an unconnected room has no local
      // participant, so there is nothing to read either clock off. Null has to
      // survive all the way to the writer -- the reader refuses to correct any
      // half of a transcript unless every half that carries words has an
      // offset, and a fabricated zero here would claim the two clocks agreed.
      expect(RealSteps().clockAnchor, isNull);
    });

    test('the offset is the DEVICE against the SFU, not the reverse', () {
      // The sign is the whole correction. Read backwards it does not fail to
      // help -- it doubles the skew, turning a thirty-second error into a
      // minute, and it does so on every call.
      final media = mediaAt(deviceAtJoin)..anchorClocksTo(sfuJoin);

      expect(media.clockAnchor?.offsetMs, 30000);
    });

    test('the FIRST reading stands for the call', () {
      // Latched, not re-read. `joinedAt` is fixed at join, so pairing it with
      // a device clock read later would measure the call's own duration and
      // shift this speaker's whole half by it. The later reading here is what
      // an unmute five minutes in would produce.
      final media = mediaAt(deviceAtJoin)
        ..anchorClocksTo(sfuJoin)
        ..anchorClocksTo(sfuJoin.subtract(const Duration(minutes: 5)));

      expect(media.clockAnchor?.offsetMs, 30000);
    });

    test('a reading that cannot be a time is no anchor at all', () {
      // Zero is the protocol default for `joinedAt`, so a server that never
      // stamped it reads as 1970 -- and the offset against 1970 is this
      // device's entire clock. Refused here rather than on the wire, so a
      // reading this app would not believe is never sent.
      final media = mediaAt(deviceAtJoin)
        ..anchorClocksTo(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));

      expect(media.clockAnchor, isNull);
    });

    test('a refused reading does not close the latch', () {
      // The latch holds an ANSWER, not the fact of having asked. Closing it on
      // a refusal would cost the correction for the whole call on the strength
      // of one early, unusable read.
      final media = mediaAt(deviceAtJoin)
        ..anchorClocksTo(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
        ..anchorClocksTo(sfuJoin);

      expect(media.clockAnchor?.offsetMs, 30000);
    });
  });
}

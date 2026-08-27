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
  int disconnects = 0;

  @override
  Future<void> connectRoom(String url, String jwt) async {
    steps.add('connect');
    if (releaseDuringConnect) await disconnect();
  }

  @override
  Future<void> enableMicrophone(bool on) async {
    steps.add('mic:$on');
    if (releaseDuringMic) {
      releaseDuringMic = false;
      await disconnect();
    }
  }

  @override
  Future<void> enableCamera(bool on) async {
    steps.add('camera:$on');
    if (cameraThrows) throw StateError('camera blocked by policy');
    if (releaseDuringCamera) {
      releaseDuringCamera = false;
      await disconnect();
    }
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

  Future<void> mic(bool on) => enableMicrophone(on);
  Future<void> cam(bool on) => enableCamera(on);
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

  test('a call whose camera came up reports no camera failure', () async {
    final media = RecordingMedia();
    await media.connect(grant, video: true);
    expect(media.cameraFailed, isFalse);
  });

  // The silent failure this replaces: `room.localParticipant?.setMicrophone`
  // returned as though the microphone had been published when there was no
  // participant to publish through, so the call connected and rang with this
  // side unable to be heard.
  test(
    'turning the microphone on with nothing to publish through says so',
    () async {
      final media = RealSteps();
      await media.mic(true);
      expect(
        media.captureRefused,
        isTrue,
        reason: 'the step did not happen, and silence about that is the bug',
      );
    },
  );

  test(
    'turning the camera on with nothing to publish through says so',
    () async {
      final media = RealSteps();
      await media.cam(true);
      expect(media.captureRefused, isTrue);
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

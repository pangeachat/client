import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';

import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/capture_election.dart';
import 'package:fluffychat/routes/chat/calls/sfu_join_stamp.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'livekit_fixtures.dart';

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
  RealSteps({super.room, super.now});

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

/// Lets a test control exactly when each microphone publish call resolves,
/// and in what order -- the only way to build the specific race
/// `CallMedia._enableCapture`'s generation guard exists to close: a hold's
/// close and the resume that follows it both reach the SDK, and nothing
/// before that guard could make the FIRST one's own call resolve after the
/// SECOND's, since a real `LocalParticipant` cannot be made to answer to
/// order.
class ManualPublishMedia extends CallMedia {
  ManualPublishMedia({required super.room});

  final _micCompleters = <Completer<bool>>[];

  /// Every `on` this was asked to publish, in the order it was asked, so a
  /// test can see the fix's own corrective call happen and what it asked for.
  final requestedMic = <bool>[];

  /// What the SDK would actually be left showing, updated in COMPLETION
  /// order -- which is the only thing a real platform's own internal state
  /// ever reflects, whichever call was ISSUED first.
  bool? micState;

  @override
  Future<bool> publishMicrophone(LocalParticipant participant, bool on) {
    requestedMic.add(on);
    // EVERY call is held open until a test resolves it by hand -- including
    // a corrective one _enableCapture's own loop makes, which needs the same
    // control as the original two: a THIRD transition racing a correction
    // is exactly the shape of the gap a cold review found in a one-shot
    // (non-looping) version of the fix.
    final completer = Completer<bool>();
    _micCompleters.add(completer);
    return completer.future.then((published) {
      if (published) micState = on;
      return published;
    });
  }

  /// Resolves the [n]th publish call (0-indexed, issue order) as though the
  /// SDK reported [published].
  void resolveMic(int n, {required bool published}) {
    _micCompleters[n].complete(published);
  }
}

/// A room with no local participant until a test says otherwise -- unlike
/// `RoomWithParticipant`, which always answers a fixed one. Lets a test put
/// a call in the exact state `_publishingAs`'s retry loop exists for: a
/// device mid-connect, with nothing yet to publish through.
class _RoomWithNoParticipantYet extends Room {
  LocalParticipant? participant;

  @override
  LocalParticipant? get localParticipant => participant;
}

void main() {
  // The participant-present test drives a real `setMicrophoneEnabled`, which
  // reaches a platform channel. Without a binding that fails as an assertion
  // outside the future and cannot be caught; with one it is an ordinary
  // MissingPluginException the test can expect.
  TestWidgetsFlutterBinding.ensureInitialized();

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
    // What the SFU put in the join response, and a device clock reading thirty
    // seconds later than the second it names -- a device thirty seconds fast.
    // The SFU joined 437ms into that second, which is what field 17 can say and
    // field 6 cannot.
    final sfuJoin = DateTime.utc(2026, 8, 26, 9);
    final sfuSecondsMs = sfuJoin.millisecondsSinceEpoch;
    final deviceAtJoin = sfuJoin.add(const Duration(seconds: 30));

    ({int secondsMs, int ms}) stamps({int? ms}) =>
        (secondsMs: sfuSecondsMs, ms: ms ?? sfuSecondsMs + 437);

    CallMedia mediaAt(DateTime deviceNow) => RealSteps(now: () => deviceNow);

    test('a call whose join response never arrived carries no anchor', () {
      // The state `RealSteps` is in: nothing was ever connected, so the watch
      // never fired. Null has to survive all the way to the writer -- the
      // reader refuses to correct any half of a transcript unless every half
      // that carries words has an offset, and a fabricated anchor here would
      // claim a measurement nobody took.
      expect(RealSteps().clockAnchor, isNull);
    });

    test('a participant in the room is not a licence to build an anchor', () async {
      // The branch the removed fallback actually sat on. It read the local
      // participant's coarse `joinedAt` and paired it with this device's clock
      // read after `Room.connect` had returned -- a pair that carried however
      // long the connect took, so two devices genuinely 100ms apart could
      // anchor seconds apart and a reply would render above the question it
      // answered, confidently, with no missing-clock notice anywhere.
      //
      // Supplying a participant is what makes this test the fallback's and not
      // merely the give-up path's: `_publishingAs` returns on its FIRST line
      // here, so a restored `_anchored(ready)` would run. `joinedAt` is set to
      // a real time so a fallback would find a usable reading and produce an
      // anchor rather than being refused for a bad one.
      //
      // Publishing then throws -- `setMicrophoneEnabled` reaches a platform
      // channel this suite has no binding for -- which is fine and is not what
      // is under test: a fallback would have run before it, so the assertion
      // after the throw is the one that matters.
      final media = RealSteps(
        room: RoomWithParticipant(await participantJoinedAt(1787734800)),
        now: () => deviceAtJoin,
      );

      await expectLater(media.mic(true), throwsA(anything));
      expect(
        media.clockAnchor,
        isNull,
        reason: 'a participant is not an observation of the two clocks',
      );
    });

    test('giving up on a participant does not invent one either', () {
      // The other half, kept because it is a different path: no participant
      // ever appears, `_publishingAs` waits and gives up, and that route must
      // not manufacture an anchor on the way out either.
      final media = mediaAt(deviceAtJoin);
      expect(media.captureRefused, isFalse);
      expect(media.clockAnchor, isNull);
    });

    test('the offset is the DEVICE against the SFU, not the reverse', () {
      // The sign is the whole correction. Read backwards it does not fail to
      // help -- it doubles the skew, turning a thirty-second error into a
      // minute, and it does so on every call.
      final media = mediaAt(deviceAtJoin)
        ..anchorClocksTo((secondsMs: sfuSecondsMs, ms: sfuSecondsMs));

      expect(media.clockAnchor?.offsetMs, 30000);
    });

    test('the FIRST reading stands for the call', () {
      // Latched, not re-read. A reconnect restamps the join, and the offset is
      // a property of the clocks rather than of any one join, so the earliest
      // self-consistent pair stands. The later reading here is what a
      // mid-call reconnect would deliver.
      final media = mediaAt(deviceAtJoin)
        ..anchorClocksTo((secondsMs: sfuSecondsMs, ms: sfuSecondsMs))
        ..anchorClocksTo((
          secondsMs: sfuSecondsMs - 300000,
          ms: sfuSecondsMs - 300000,
        ));

      expect(media.clockAnchor?.offsetMs, 30000);
    });

    test('a reading that cannot be a time is no anchor at all', () {
      // Zero is the protocol default, so a server that never stamped the join
      // reads as 1970 -- and the offset against 1970 is this device's entire
      // clock. Refused here rather than on the wire, so a reading this app
      // would not believe is never sent.
      final media = mediaAt(deviceAtJoin)
        ..anchorClocksTo((secondsMs: 0, ms: 0));

      expect(media.clockAnchor, isNull);
    });

    test('a refused reading does not close the latch', () {
      // The latch holds an ANSWER, not the fact of having asked. Closing it on
      // a refusal would cost the correction for the whole call on the strength
      // of one early, unusable read.
      final media = mediaAt(deviceAtJoin)
        ..anchorClocksTo((secondsMs: 0, ms: 0))
        ..anchorClocksTo((secondsMs: sfuSecondsMs, ms: sfuSecondsMs));

      expect(media.clockAnchor?.offsetMs, 30000);
    });

    test('the reading is paired the moment the watcher hands it over', () {
      // The half the listener count cannot see, and the regression that got
      // through twice: a version that stored the stamps and paired them with a
      // clock read after `connect` subscribed in the constructor exactly like
      // this one, so counting subscriptions said nothing about it.
      //
      // The watcher is replaced, so the callback CallMedia actually hands over
      // can be invoked directly -- a real join response cannot be delivered
      // through a real room. The clock ADVANCES a second per read, so a later
      // reading is a different number: pairing at the moment of the callback
      // gives deviceMs == the first read, and anything that defers gives a
      // later one.
      late void Function(({int secondsMs, int ms})) handedOver;
      var reads = 0;
      final media = CallMedia(
        now: () => sfuJoin.add(Duration(seconds: reads++)),
        watchJoinStamp: (room, onStamp) {
          handedOver = onStamp;
          return () async {};
        },
      );

      // Nothing yet: constructing must not read the clock or invent an anchor.
      expect(media.clockAnchor, isNull);
      expect(reads, 0);

      handedOver((secondsMs: sfuSecondsMs, ms: sfuSecondsMs + 437));

      expect(media.clockAnchor?.sfuMs, sfuSecondsMs + 437);
      expect(
        media.clockAnchor?.deviceMs,
        sfuSecondsMs,
        reason: 'the device half must be the clock read AT the callback',
      );
      expect(reads, 1, reason: 'exactly one clock read, taken there and then');
    });

    test('the watches are live before anything could connect', () {
      // That the REAL watchers are the defaults, and that they are attached
      // before anything could connect. The test above replaces one of them, so
      // it would pass just as well against a default that subscribed to
      // nothing; this one uses a real `Room` and counts what actually landed on
      // its signal emitter.
      //
      // WHAT NEITHER TEST CAN SEE, stated so nobody reads them as more than
      // they are: that livekit_client still emits `SignalJoinResponseEvent`,
      // and that it emits before `Room.connect` returns. Both are livekit's
      // behaviour, not ours, and a join response cannot be delivered through a
      // real room here — emitting on its signal emitter wakes livekit's own
      // handler, which reaches a platform channel. Only a real two-device call
      // covers that last gap; a rename or a move fails at analysis time.
      // A DELTA, not a count. livekit_client subscribes to that emitter itself
      // when the `SignalClient` is built, so the absolute number is not ours to
      // predict -- asserting one was this test's own first failure.
      //
      // THREE: the clock anchor's join-stamp watch, and the participant-stamp
      // watch's two -- the join response and the later updates are separate
      // frames. Both attaches are constructor-time and for the same reason: the
      // join response is the only frame guaranteed to name the devices already
      // in the room, so a subscription opened after the connect may never hear
      // of them.
      final room = Room();
      final before = joinStampWatchCount(room);

      CallMedia(room: room);
      expect(
        joinStampWatchCount(room) - before,
        3,
        reason: 'constructing the media must attach both stamp watches',
      );
    });

    test('BOTH watches are given back when the call is disposed', () async {
      // The claim this replaces was `expect(media.dispose(), completes)`, which
      // proved only that teardown did not throw -- it never checked that the
      // subscription was released. Asserted through the injected watchers
      // because that is the only way to see the cancellers themselves run: a
      // real room disposes its own emitter, which would clear the listeners
      // whether or not this object gave them back.
      var joinCancelled = false;
      var participantsCancelled = false;
      final media = CallMedia(
        watchJoinStamp: (room, onStamp) =>
            () async => joinCancelled = true,
        watchParticipantStamps: (room, onStamps) =>
            () async => participantsCancelled = true,
      );

      expect(joinCancelled, isFalse);
      expect(participantsCancelled, isFalse);
      await media.dispose();
      expect(joinCancelled, isTrue);
      expect(participantsCancelled, isTrue);
    });

    group('what the anchor makes of a pair of stamps', () {
      test('is what the offset is measured against when it is sent', () {
        // 29563, not 30000. The 437ms is what the fine stamp is worth once it
        // reaches here; whether it reaches here at all is the seam's business
        // and is tested there, not in this file.
        final media = mediaAt(deviceAtJoin)..anchorClocksTo(stamps());

        expect(media.clockAnchor?.sfuMs, sfuSecondsMs + 437);
        expect(media.clockAnchor?.offsetMs, 29563);
      });

      test('a server that sends no fine stamp still anchors', () {
        // An SFU older than livekit-server v1.8.4, which the probe confirms
        // omits field 17 entirely. This test starts at `ms: 0` and covers only
        // what the anchor does with it: the SFU half falls back to the coarse
        // stamp, which is all that server said, and the DEVICE half is
        // unaffected because it was read at the join either way. The step
        // BEFORE this -- an absent field 17 arriving as zero, which is proto3
        // leaving defaults off the wire -- is the extractor's, and is proven in
        // `sfu_join_stamp_test.dart`. Neither test covers the path end to end;
        // together they cover it.
        //
        // The fallback is sound precisely because it does not change WHEN
        // either half was read.
        final media = mediaAt(deviceAtJoin)..anchorClocksTo(stamps(ms: 0));

        expect(media.clockAnchor?.sfuMs, sfuSecondsMs);
        expect(media.clockAnchor?.offsetMs, 30000);
      });

      test('a fine stamp that contradicts the coarse one is refused', () {
        // `joined_at` is `joined_at_ms` truncated to the second, and both come
        // out of the SAME frame, so a fine stamp more than 999ms past the
        // coarse one is a server contradicting itself. Falls back to the coarse
        // stamp rather than being repaired, because a refinement that does not
        // refine is not a better answer, it is a different one.
        //
        // The OFFSET is asserted, not just the SFU half. The claim being made
        // is that a bad fine stamp costs precision and nothing else, and only
        // the offset can show that the device half survived intact -- checking
        // `sfuMs` alone would pass just as well if the pairing had been lost.
        for (final wrong in <int>[
          sfuSecondsMs - 1,
          sfuSecondsMs + 1000,
          sfuSecondsMs + 60000,
          ClockAnchor.clockCeilingMs,
        ]) {
          final media = mediaAt(deviceAtJoin)
            ..anchorClocksTo(stamps(ms: wrong));

          expect(
            media.clockAnchor?.sfuMs,
            sfuSecondsMs,
            reason: '$wrong is not a finer reading of this join',
          );
          expect(
            media.clockAnchor?.offsetMs,
            30000,
            reason: '$wrong must cost precision and nothing else',
          );
        }
      });

      test('cannot rescue a coarse reading the anchor refuses', () {
        // A REFINEMENT ONLY. Zero seconds is the unstamped protocol default,
        // and an offset measured against 1970 is this device's entire clock
        // rather than its disagreement with anything — so the anchor refuses
        // it. A millisecond field arriving beside it must not turn that
        // refusal into an answer, however well-formed it looks on its own.
        final media = mediaAt(deviceAtJoin)
          ..anchorClocksTo((secondsMs: 0, ms: 437));

        expect(media.clockAnchor, isNull);
      });
    });
  });

  group('the SFU join stamps this call holds for other devices', () {
    const mine = '@ann:pangea.chat:MINE';
    const sibling = '@ann:pangea.chat:SIBLING';

    final sfuJoin = DateTime.utc(2026, 8, 26, 9);
    final sfuSecondsMs = sfuJoin.millisecondsSinceEpoch;

    /// The media, plus the callback it actually handed the participant watch.
    ///
    /// Through the injected seam for the same reason the anchor's pairing test
    /// uses one: calling [CallMedia.recordJoinStamps] by hand proves a reading
    /// is stored and says nothing about WHICH callback this object subscribed
    /// with. A version that subscribed with an empty closure would pass every
    /// assertion below if they were made by hand.
    (CallMedia, void Function(List<SfuParticipantStamps>)) mediaWatching() {
      late void Function(List<SfuParticipantStamps>) handedOver;
      final media = CallMedia(
        watchParticipantStamps: (room, onStamps) {
          handedOver = onStamps;
          return () async {};
        },
      );
      return (media, handedOver);
    }

    test('holds what the server said, keyed by the identity it said it of', () {
      // RAW, both halves. The fine half of the sibling here is zero because an
      // SFU older than livekit-server v1.8.4 never sets field 17, and that is
      // an ordinary answer rather than a fault -- so it is passed on rather
      // than repaired, and the coarse half stays beside it so a reader can tell
      // a refinement from a contradiction without a second source.
      final (media, handedOver) = mediaWatching();

      expect(media.sfuJoinStampsFor(sibling), isNull);

      handedOver([
        (
          identity: mine,
          secondsMs: sfuSecondsMs,
          ms: sfuSecondsMs + 437,
          sid: 'PA_mine',
          version: 1,
          hasLeft: false,
        ),
        (
          identity: sibling,
          secondsMs: sfuSecondsMs - 2000,
          ms: 0,
          sid: 'PA_sib',
          version: 1,
          hasLeft: false,
        ),
      ]);

      expect(media.sfuJoinStampsFor(mine), (
        secondsMs: sfuSecondsMs,
        ms: sfuSecondsMs + 437,
      ));
      expect(media.sfuJoinStampsFor(sibling), (
        secondsMs: sfuSecondsMs - 2000,
        ms: 0,
      ));
    });

    test('a device nothing has named is unknown, never zero', () {
      // The distinction the whole store rests on. Zero is a server that said
      // nothing about the millisecond field while still naming the device;
      // absent is nobody having named the device at all. A reader that got
      // zeros for a device it has never heard of would be told a join time of
      // 1970 for a device that may have joined before it.
      final (media, handedOver) = mediaWatching();

      handedOver([
        (
          identity: mine,
          secondsMs: sfuSecondsMs,
          ms: sfuSecondsMs + 437,
          sid: 'PA_mine',
          version: 1,
          hasLeft: false,
        ),
      ]);

      expect(media.sfuJoinStampsFor(sibling), isNull);
    });

    test('the LATEST statement about a device is the one held', () {
      // livekit_client's own `Participant.joinedAt` reads whichever
      // `ParticipantInfo` it last accepted, so keeping the first here would
      // leave this and the coarse reading every other caller takes off the
      // participant describing different frames. Here the later statement is a
      // fresh session for the same identity — a rejoin — with a join a minute
      // on; its new sid means the version guard does not mistake it for the old
      // session going backwards, so the newer join is the one held.
      final (media, handedOver) = mediaWatching();

      handedOver([
        (
          identity: sibling,
          secondsMs: sfuSecondsMs,
          ms: 0,
          sid: 'PA_first',
          version: 3,
          hasLeft: false,
        ),
      ]);
      handedOver([
        (
          identity: sibling,
          secondsMs: sfuSecondsMs + 60000,
          ms: sfuSecondsMs + 60012,
          sid: 'PA_second',
          version: 0,
          hasLeft: false,
        ),
      ]);

      expect(media.sfuJoinStampsFor(sibling), (
        secondsMs: sfuSecondsMs + 60000,
        ms: sfuSecondsMs + 60012,
      ));
    });

    test('a stamp recorded here never becomes a clock anchor', () {
      // The separation the two watches exist for. These stamps also arrive on
      // participant updates, which restate a join from some earlier and
      // unknowable moment -- so a pair built here would measure the time since
      // that join rather than the disagreement between two clocks, which is the
      // failure `anchorClocksTo` refuses a fallback over.
      //
      // The stamp is a real, self-consistent time and the clock is the default
      // one, so an anchor WOULD be built if this path reached it. Null here is
      // the absence of a route, not a reading being refused.
      final (media, handedOver) = mediaWatching();

      handedOver([
        (
          identity: mine,
          secondsMs: sfuSecondsMs,
          ms: sfuSecondsMs + 437,
          sid: 'PA_mine',
          version: 1,
          hasLeft: false,
        ),
      ]);

      expect(media.clockAnchor, isNull);
    });

    group('a superseded statement never overwrites the live join', () {
      // The store feeds `CaptureElection`, which DESTROYS a learner's captured
      // audio when a sibling's join sorts before this device's. A learner's
      // device can leave a call and rejoin under the same identity, and the
      // ended session's updates can still be in flight — so "latest wins" is
      // wrong for exactly the frames that arrive out of order, and wrong here
      // means audio nobody else holds is thrown away.
      const me = '@ann:pangea.chat:MINE';
      const sib = '@ann:pangea.chat:SIBLING';

      /// Where the sibling's join sits after the store has seen [updates], read
      /// back the way the election reads it.
      ({int secondsMs, int ms})? siblingJoinAfter(
        List<SfuParticipantStamps> Function() updates,
      ) {
        final (media, handedOver) = mediaWatching();
        handedOver(updates());
        return media.sfuJoinStampsFor(sib);
      }

      test('a DISCONNECTED update cannot drag a rejoin back to the old join', () {
        // The destroying sequence at its source. The sibling rejoined at
        // +3000ms; its earlier session's DISCONNECTED notice, carrying the join
        // 5s before, then lands late. Applied, it would move the sibling's join
        // back before ours and hand the election a reason to discard our tail.
        final (media, handedOver) = mediaWatching();

        // The rejoin: the current session, a join AFTER ours.
        handedOver([
          (
            identity: sib,
            secondsMs: sfuSecondsMs + 3000,
            ms: sfuSecondsMs + 3100,
            sid: 'PA_second',
            version: 0,
            hasLeft: false,
          ),
        ]);
        // The delayed word from the session that ENDED: an earlier join, and
        // marked as having left.
        handedOver([
          (
            identity: sib,
            secondsMs: sfuSecondsMs - 5000,
            ms: sfuSecondsMs - 4900,
            sid: 'PA_first',
            version: 9,
            hasLeft: true,
          ),
        ]);

        expect(
          media.sfuJoinStampsFor(sib),
          (secondsMs: sfuSecondsMs + 3000, ms: sfuSecondsMs + 3100),
          reason: 'a departed session must not overwrite the live rejoin',
        );
      });

      test('a departed statement is refused even when its join is LATER', () {
        // What `hasLeft` guards that the newer-session rule cannot. The session
        // order the store keeps is by join instant, so a departed statement
        // carrying an EARLIER join is already refused as an older session -- but
        // a departed statement can also carry a LATER join (a ghost session, or
        // a leave whose own join we never saw), and by instant alone that reads
        // as newer and would be taken. It describes a device that has LEFT, so
        // it must not move the live join regardless of how late it claims to be.
        final (media, handedOver) = mediaWatching();
        // The live session.
        handedOver([
          (
            identity: sib,
            secondsMs: sfuSecondsMs + 3000,
            ms: sfuSecondsMs + 3100,
            sid: 'PA_live',
            version: 0,
            hasLeft: false,
          ),
        ]);
        // A departed statement claiming a LATER join. By instant it looks like a
        // newer session; only `hasLeft` keeps it out.
        handedOver([
          (
            identity: sib,
            secondsMs: sfuSecondsMs + 9000,
            ms: sfuSecondsMs + 9100,
            sid: 'PA_ghost',
            version: 0,
            hasLeft: true,
          ),
        ]);

        expect(
          media.sfuJoinStampsFor(sib),
          (secondsMs: sfuSecondsMs + 3000, ms: sfuSecondsMs + 3100),
          reason: 'a device that has left never moves the live join',
        );
      });

      test('an out-of-order frame for the SAME session is ignored', () {
        // The KNOWN LIMIT the store used to carry: livekit_client refuses an
        // update with a lower version for a session it already holds
        // (participant.dart:221) and this did not. A reordered frame — same
        // sid, lower version, an earlier join — must not walk the store back.
        expect(
          siblingJoinAfter(
            () => [
              (
                identity: sib,
                secondsMs: sfuSecondsMs + 3000,
                ms: sfuSecondsMs + 3100,
                sid: 'PA_one',
                version: 7,
                hasLeft: false,
              ),
              (
                identity: sib,
                secondsMs: sfuSecondsMs - 5000,
                ms: sfuSecondsMs - 4900,
                sid: 'PA_one',
                version: 4,
                hasLeft: false,
              ),
            ],
          ),
          (secondsMs: sfuSecondsMs + 3000, ms: sfuSecondsMs + 3100),
          reason: 'a lower version for a held session is stale',
        );
      });

      test('a fresh session with a restarted version still lands', () {
        // The guard is gated on the sid so it cannot swallow a real rejoin: a
        // new session restarts the version counter, and version 0 of PA_second
        // is not version 0 of PA_first going backwards. The later join wins.
        expect(
          siblingJoinAfter(
            () => [
              (
                identity: sib,
                secondsMs: sfuSecondsMs,
                ms: sfuSecondsMs + 10,
                sid: 'PA_first',
                version: 8,
                hasLeft: false,
              ),
              (
                identity: sib,
                secondsMs: sfuSecondsMs + 3000,
                ms: sfuSecondsMs + 3100,
                sid: 'PA_second',
                version: 0,
                hasLeft: false,
              ),
            ],
          ),
          (secondsMs: sfuSecondsMs + 3000, ms: sfuSecondsMs + 3100),
          reason: 'a rejoin under a fresh sid is not an out-of-order frame',
        );
      });

      test('an older session under a DIFFERENT sid cannot overwrite the '
          'rejoin', () {
        // The gap a same-sid version check cannot close, and the same
        // audio-destroying move as the disconnected case through a different
        // door. A rejoin lands under a FRESH sid, so the ended session's late
        // word carries a different sid and slips past a version comparison
        // entirely -- and it need not be marked disconnected. It still names an
        // EARLIER join, and letting it overwrite moves the store back to a join
        // the device no longer holds, which is what lets the election read a
        // live device as present before a sibling it in fact joined after.
        final (media, handedOver) = mediaWatching();
        // The old session.
        handedOver([
          (
            identity: sib,
            secondsMs: sfuSecondsMs,
            ms: sfuSecondsMs + 10,
            sid: 'PA_old',
            version: 1,
            hasLeft: false,
          ),
        ]);
        // The rejoin: a fresh sid, a later join.
        handedOver([
          (
            identity: sib,
            secondsMs: sfuSecondsMs + 3000,
            ms: sfuSecondsMs + 3100,
            sid: 'PA_new',
            version: 0,
            hasLeft: false,
          ),
        ]);
        // The old session's delayed, NON-disconnected word: a different sid, an
        // earlier join, and a high version a same-sid check would have deferred
        // to.
        handedOver([
          (
            identity: sib,
            secondsMs: sfuSecondsMs,
            ms: sfuSecondsMs + 10,
            sid: 'PA_old',
            version: 9,
            hasLeft: false,
          ),
        ]);

        expect(
          media.sfuJoinStampsFor(sib),
          (secondsMs: sfuSecondsMs + 3000, ms: sfuSecondsMs + 3100),
          reason:
              'an older session under a different sid is not a newer session',
        );
      });

      test(
        'the stale stamp can no longer make the election discard our tail',
        () {
          // END TO END, through the exact wiring `ActiveCall` uses: the store is
          // fed the rejoin then the delayed departed frame, and the election is
          // handed the join stamps straight out of the store — the same call
          // `discardsCapturedAudio` gets at active_call.dart. Everything else is
          // arranged so the ONLY thing the discard can turn on is the sibling's
          // stored join: the sibling attests a run our watch saw open and hold,
          // and the coarse joins are withheld so the millisecond stamps decide.
          //
          // We recorded our tail from +0ms; the sibling truly rejoined at
          // +3000ms, so our tail is audio the sibling was not in the room for.
          // With the store corrupted back to -5000ms the election read the
          // sibling as first and discarded that tail. It must now keep it.
          final (media, handedOver) = mediaWatching();
          handedOver([
            (
              identity: sib,
              secondsMs: sfuSecondsMs + 3000,
              ms: sfuSecondsMs + 3100,
              sid: 'PA_second',
              version: 0,
              hasLeft: false,
            ),
          ]);
          handedOver([
            (
              identity: sib,
              secondsMs: sfuSecondsMs - 5000,
              ms: sfuSecondsMs - 4900,
              sid: 'PA_first',
              version: 9,
              hasLeft: true,
            ),
          ]);
          handedOver([
            (
              identity: me,
              secondsMs: sfuSecondsMs,
              ms: sfuSecondsMs,
              sid: 'PA_me',
              version: 0,
              hasLeft: false,
            ),
          ]);

          const successor = CaptureCandidate('SIBLING');
          final report = CaptureReport.of(
            'SIBLING',
            CaptureReport.published('r1'),
          );

          bool discards() => CaptureElection.discardsCapturedAudio(
            successor: successor,
            successorReport: report,
            watch: CaptureWatch()..observe([report]),
            mySfuStamps: media.sfuJoinStampsFor(me),
            successorSfuStamps: media.sfuJoinStampsFor(sib),
          );

          expect(
            discards(),
            isFalse,
            reason: 'the live rejoin is after our join, so our tail is ours',
          );

          // The tripwire the fix removed. Recorded blindly, the departed frame
          // would leave the sibling at -4900ms and the election would take our
          // tail — so this asserts the corrupted store IS what destroys it,
          // which is what makes the assertion above a proof rather than a
          // coincidence.
          expect(
            CaptureElection.discardsCapturedAudio(
              successor: successor,
              successorReport: report,
              watch: CaptureWatch()..observe([report]),
              mySfuStamps: media.sfuJoinStampsFor(me),
              successorSfuStamps: (
                secondsMs: sfuSecondsMs - 5000,
                ms: sfuSecondsMs - 4900,
              ),
            ),
            isTrue,
            reason: 'the stale join is what the discard would have fired on',
          );
        },
      );
    });
  });
  group('the held gate refuses opens, and wins any race with one', () {
    // The real steps reach `setMicrophoneEnabled`, which hits a platform channel
    // this suite has no binding for and THROWS. So a completed `false` is proof
    // the gate returned before the publish; a throw would mean it did not.
    test(
      'an entry-time hold refuses the microphone open, publishing nothing',
      () async {
        final media = RealSteps(
          room: RoomWithParticipant(await participantJoinedAt(1787734800)),
        );
        media.captureHeld = true;
        expect(await media.mic(true), isFalse);
      },
    );

    test('an entry-time hold refuses the camera open too', () async {
      final media = RealSteps(
        room: RoomWithParticipant(await participantJoinedAt(1787734800)),
      );
      media.captureHeld = true;
      expect(await media.cam(true), isFalse);
    });

    test('a hold that lands MID-open still publishes nothing (TOCTOU)', () async {
      // `enableMicrophone` suspends at `await _publishingAs`, so flipping the
      // hold on the next synchronous line lands it after the acquire and before
      // the publish -- exactly the window an entry-only check would miss. The
      // re-check after the acquire must catch it and return before the publish,
      // so no platform-channel throw escapes.
      final media = RealSteps(
        room: RoomWithParticipant(await participantJoinedAt(1787734800)),
      );
      media.captureHeld = false;
      final open = media.mic(true);
      media.captureHeld = true;
      expect(await open, isFalse);
    });

    test('a hold that lands mid-open refuses the camera too', () async {
      final media = RealSteps(
        room: RoomWithParticipant(await participantJoinedAt(1787734800)),
      );
      media.captureHeld = false;
      final open = media.cam(true);
      media.captureHeld = true;
      expect(await open, isFalse);
    });

    test('a hold never refuses a CLOSE', () async {
      // Only opens are gated; closing must always be allowed, or a held device
      // could never be muted in the first place.
      final media = RealSteps(
        room: RoomWithParticipant(await participantJoinedAt(1787734800)),
      );
      media.captureHeld = true;
      expect(
        await media.mic(false),
        isFalse,
      ); // false = nothing to stop, not refused
    });
  });

  group('capture transitions -- the LATEST one wins the SDK, not whichever '
      'resolves last', () {
    // The hold's own close comment says close wins DURING a hold because it
    // is re-asserted every held tick -- but resume is a ONE-TIME edge, never
    // re-fired later, so a stale close from an EARLIER tick that is still in
    // flight when the resume's open is issued has nothing else re-asserting
    // over it. Without the generation guard in `_enableCapture`, whichever
    // one's own SDK call happened to resolve last decided the microphone --
    // not whichever was actually asked for last.
    test("a hold's close that resolves AFTER the resume's open still ends up "
        'unmuted', () async {
      final participant = await participantJoinedAt(1787734800);
      final media = ManualPublishMedia(room: RoomWithParticipant(participant));

      // The hold closes the microphone -- its own SDK call is left
      // hanging, deliberately, so it is the one that resolves LAST.
      final closing = media.setMicrophoneEnabled(false);
      // The resume that follows, before the close has settled at all.
      final opening = media.setMicrophoneEnabled(true);
      // Both calls suspend at `await _publishingAs` before they ever
      // reach the SDK (see the TOCTOU test above) -- pumped once so both
      // land on their own publish call and are the ones under test's
      // control, rather than still queued behind that first await.
      await pumpEventQueue();
      expect(
        media.requestedMic,
        [false, true],
        reason: 'both transitions reach the SDK -- nothing blocks either',
      );

      // The LATER transition's own SDK call is free to resolve FIRST.
      media.resolveMic(1, published: true);
      expect(await opening, isTrue, reason: 'the resume is the latest intent');
      expect(media.micState, isTrue, reason: 'the resume has taken, for now');

      // Only NOW does the STALE close's own call resolve.
      media.resolveMic(0, published: true);
      // The correction _enableCapture's loop makes on discovering it was
      // superseded is itself one more publish call, held open exactly like
      // the first two -- pumped once so it exists to be resolved.
      await pumpEventQueue();
      expect(
        media.requestedMic,
        [false, true, true],
        reason:
            'the correction is one more publish call, asking for what is '
            'actually wanted',
      );
      media.resolveMic(2, published: true);
      expect(
        await closing,
        isFalse,
        reason: 'a superseded transition never reports success',
      );

      // The whole point: whichever call's own SDK op happened to land
      // last, the microphone ends up matching the LATEST intent, not the
      // stale one -- the stale close, discovering it was superseded,
      // corrects the microphone rather than leaving it clobbered.
      expect(
        media.micState,
        isTrue,
        reason: 'the survivor is heard, not silently re-muted',
      );
    });

    // A cold review found this gap in an earlier, non-looping version of the
    // fix: the correction is itself a publish call that can be in flight
    // when a STILL NEWER transition starts and even finishes, so a one-shot
    // correction can land last and clobber that third transition exactly as
    // the original close clobbered the open. Three in a row -- close, open,
    // close -- makes it concrete: the middle one's correction to "open" must
    // not survive the third transition's own "close" finishing first.
    test("a correction that resolves AFTER a THIRD transition must not clobber "
        'it either', () async {
      final participant = await participantJoinedAt(1787734800);
      final media = ManualPublishMedia(room: RoomWithParticipant(participant));

      // A: close. Left hanging -- this is the one whose OWN correction
      // will be made to resolve last, at the very end.
      final a = media.setMicrophoneEnabled(false);
      // B: open, before A settles.
      final b = media.setMicrophoneEnabled(true);
      await pumpEventQueue();
      expect(media.requestedMic, [false, true]);

      // B resolves. Not yet superseded by anything -- it reports success,
      // and the microphone reads open.
      media.resolveMic(1, published: true);
      expect(await b, isTrue);
      expect(media.micState, isTrue);

      // A resolves next, discovers it was superseded by B, and starts its
      // OWN correction to "open" -- held open rather than let it resolve
      // yet, because C has to start and finish INSIDE that window.
      media.resolveMic(0, published: true);
      await pumpEventQueue();
      expect(media.requestedMic, [
        false,
        true,
        true,
      ], reason: "A's correction, asking for what B wanted");

      // C: a THIRD transition, a close, starts and resolves COMPLETELY
      // while A's correction (index 2) is still in flight.
      final c = media.setMicrophoneEnabled(false);
      await pumpEventQueue();
      expect(media.requestedMic, [false, true, true, false]);
      media.resolveMic(3, published: true);
      expect(await c, isTrue, reason: 'C is the latest intent now');
      expect(
        media.micState,
        isFalse,
        reason: 'C actually closed the microphone',
      );

      // Only NOW does A's stale correction (asking for "open") resolve.
      // `a` itself is NOT awaited yet: the point of the fix is that this
      // correction's own resolution does not end the loop -- it must
      // discover ITSELF superseded (by C, not just by B) and correct
      // again, so awaiting `a` here, before that second correction has
      // even been resolved, would hang rather than prove anything.
      media.resolveMic(2, published: true);
      await pumpEventQueue();
      expect(
        media.requestedMic,
        [false, true, true, false, false],
        reason:
            "A's first correction is itself superseded by C and corrects "
            'again, back to closed, rather than stopping at one '
            'correction',
      );

      // A's SECOND correction resolves. Only now can the loop converge.
      media.resolveMic(4, published: true);
      expect(
        await a,
        isFalse,
        reason: 'A was superseded, first by B and then again by C',
      );
      expect(
        media.micState,
        isFalse,
        reason:
            'the microphone ends up matching C, the true latest intent -- '
            "not stuck on A's one-shot correction to what B wanted",
      );
    });

    // A SECOND cold review found this gap in the loop above once it started
    // correcting in both directions: closing was always unguarded because
    // closing was always safe, but generalising the correction means a
    // CLOSE can now correct itself into an OPEN -- the one direction
    // [connect] and [_setCapture] exist to guard -- and neither of those
    // wraps a correction an unrelated transition's loop makes internally.
    // Unguarded, a stale close's correction could republish the microphone
    // on a device the call has already given back.
    test('a correction never reopens the microphone once the device is '
        'released', () async {
      final participant = await participantJoinedAt(1787734800);
      final media = ManualPublishMedia(room: RoomWithParticipant(participant));

      // A: close. Left hanging.
      final a = media.setMicrophoneEnabled(false);
      // B: open, before A settles -- so A's eventual correction would
      // otherwise ask for "open", exactly as in the test above.
      final b = media.setMicrophoneEnabled(true);
      await pumpEventQueue();
      expect(media.requestedMic, [false, true]);

      media.resolveMic(1, published: true);
      expect(await b, isTrue);
      expect(media.micState, isTrue);

      // The call ends -- this device is released -- while A is still
      // hanging. Nothing about the room being given back goes through
      // `_enableCapture` at all, so this is the only way a real hangup
      // reaches it.
      await media.disconnect();

      // Only now does A's stale close resolve. Superseded by B, exactly
      // as in the test above -- but this time there is no correction to
      // make, because a released device settles on closed rather than on
      // whatever B last wanted.
      media.resolveMic(0, published: true);
      expect(await a, isFalse, reason: 'A was superseded by B');
      expect(
        media.requestedMic,
        [false, true],
        reason:
            'no correction was ever issued -- a released device is never '
            'corrected back open, whatever was last wanted',
      );
    });

    // A THIRD cold review found this gap: a call that finds no participant
    // yet (RoomWithParticipant cannot build one, since it always answers a
    // fixed one -- this needs a room that starts with none) bails out
    // BEFORE the generation stamp used to be written, so it never
    // registered its own intent at all. A sibling still waiting in
    // `_publishingAs`'s own retry loop would then find no newer generation
    // once a participant finally arrived, and apply an intent the other
    // side had already superseded.
    test('a close that finds no participant yet still registers, so a slower '
        'open cannot clobber it once one arrives', () async {
      final participant = await participantJoinedAt(1787734800);
      final room = _RoomWithNoParticipantYet();
      final media = ManualPublishMedia(room: room);

      // A: open, issued while there is no participant at all -- it sits
      // in `_publishingAs`'s retry loop.
      final a = media.setMicrophoneEnabled(true);
      // B: close, issued moments later, ALSO finds no participant -- and
      // must register its own intent regardless, since it never reaches
      // its own publish call to do so any other way.
      final b = media.setMicrophoneEnabled(false);
      await pumpEventQueue();
      expect(await b, isFalse, reason: 'nothing to close yet either');
      expect(
        media.requestedMic,
        isEmpty,
        reason: 'neither has a participant to publish through yet',
      );

      // The participant arrives inside A's retry window.
      room.participant = participant;
      // One real retry tick (100ms) so `_publishingAs` observes it.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();
      expect(
        media.requestedMic,
        [true],
        reason:
            "A finally reaches its own publish, asking for what IT "
            'wanted',
      );
      media.resolveMic(0, published: true);
      await pumpEventQueue();
      expect(
        media.requestedMic,
        [true, false],
        reason:
            "A discovers B's intent superseded it and corrects to closed "
            'rather than returning open',
      );
      media.resolveMic(1, published: true);

      expect(await a, isFalse, reason: 'A was superseded by B');
      expect(
        media.micState,
        isFalse,
        reason:
            'the microphone ends up matching B, the true latest '
            'intent',
      );
    });
  });
}

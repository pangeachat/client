import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' show AudioTrack;
import 'package:matrix/matrix.dart' as matrix show Room;
import 'package:matrix/matrix.dart' hide Room;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_roster.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// Records the order every step ran in, which is the property under test: the
/// call comes up in one order and down in the reverse, and the failure paths
/// have to preserve that.
class Trace {
  final List<String> steps = [];
  void call(String step) => steps.add(step);
}

class FakeCalls extends CallService {
  final Trace trace;

  /// The SFU's roster, which is now the only source of presence. The knobs
  /// below write into it, so a test still describes the world in terms of
  /// "my devices" and "is the peer here".
  FakeRoster? roster;

  List<String> _devices = const [];
  bool _remote = false;

  /// Devices of THIS account in the call, this one included — the way a test
  /// naturally describes it. Our own id is dropped on the way in, because the
  /// SFU only ever lists other participants.
  List<String> get devicesInCall => _devices;
  set devicesInCall(List<String> value) {
    _devices = value;
    _syncRoster();
  }

  bool get remotePresent => _remote;
  set remotePresent(bool value) {
    _remote = value;
    _syncRoster();
  }

  void _syncRoster() {
    final r = roster;
    if (r == null) return;
    final me = client.deviceID;
    r.identities = {
      for (final device in _devices)
        if (device != me) '${client.userID}:$device',
      if (_remote) '@peer:server:PEERDEVICE',
    };
    // A real roster notifies the moment the SFU's list changes.
    r.recompute();
  }

  final _declines = StreamController<Event>.broadcast();
  String? ringedNotificationId;

  /// Held open to reproduce a hangup landing mid-step.
  Completer<void>? holdRing;
  Completer<void>? holdJoin;
  Completer<void>? holdAnnounce;

  /// Whether anything is still subscribed for declines. A subscription made
  /// after teardown has nothing left able to cancel it.
  bool get watchingForDeclines => _declines.hasListener;

  @override
  Future<String?> ring(
    matrix.Room room, {
    required String membershipEventId,
    required bool video,
  }) async {
    trace('ring');
    if (holdRing != null) await holdRing!.future;
    return ringedNotificationId ??= '\$notification';
  }

  @override
  Stream<Event> declinesIn(matrix.Room room) => _declines.stream;

  final _rings = StreamController<Event>.broadcast();

  @override
  Stream<Event> ringsIn(matrix.Room room) => _rings.stream;

  /// The other person calling us at the same moment we call them.
  ///
  /// A real notification, because only a live one counts: sync replays old
  /// events, and a call from an hour ago is not somebody calling now.
  Future<void> peerAlsoCalls({Duration age = Duration.zero}) async {
    final sentAt = DateTime.now().subtract(age);
    _rings.add(
      Event(
        type: PangeaEventTypes.callNotification,
        content: {
          'application': {
            'type': 'm.call',
            'notification_type': 'ring',
            'sender_ts': sentAt.millisecondsSinceEpoch,
            'lifetime': 30000,
          },
          'm.relates_to': {
            'rel_type': 'm.reference',
            'event_id': '\$theirmembership',
          },
        },
        eventId: '\$theirs',
        senderId: '@peer:server',
        originServerTs: sentAt,
        room: matrix.Room(id: '!r:server', client: client),
      ),
    );
    await pumpEventQueue();
  }

  @override
  String? declineTarget(Event event) =>
      (event.content['m.relates_to'] as Map?)?['event_id'] as String?;

  /// A decline from an earlier call, replayed out of the room's history the way
  /// sync replays one.
  Future<void> peerDeclinedLongAgo() async {
    _declines.add(
      Event(
        type: 'decline',
        content: const {
          'm.relates_to': {
            'rel_type': 'm.reference',
            'event_id': '\$someoldcall',
          },
        },
        eventId: '\$old',
        senderId: '@peer:server',
        originServerTs: DateTime.now().subtract(const Duration(hours: 1)),
        room: matrix.Room(id: '!r:server', client: client),
      ),
    );
    await pumpEventQueue();
  }

  /// The other person turning down the call this device rang.
  Future<void> peerDeclines() async {
    _declines.add(
      Event(
        type: 'decline',
        content: {
          'm.relates_to': {
            'rel_type': 'm.reference',
            'event_id': ringedNotificationId ?? '\$notification',
          },
        },
        eventId: '\$d',
        senderId: '@peer:server',
        originServerTs: DateTime.now(),
        room: matrix.Room(id: '!r:server', client: client),
      ),
    );
    await pumpEventQueue();
  }

  /// Publishes a new participant list, the way a join or leave would.
  Future<void> participantsBecome(List<String> ids) async {
    devicesInCall = ids;
    await pumpEventQueue();
  }

  Object? joinError;
  Object? announceError;
  Object? retractError;
  bool retractFails = false;

  FakeCalls(super.client, this.trace);

  @override
  Future<CallToken> join(matrix.Room room) async {
    trace('join');
    if (holdJoin != null) await holdJoin!.future;
    if (joinError != null) throw joinError!;
    return const CallToken(jwt: 'jwt', url: 'ws://sfu');
  }

  /// The membership this account holds, as the room would report it. Overridden
  /// because the real one reaches into the SDK, which a unit test has no
  /// business standing up.
  bool _retracted = false;

  /// What the ROOM reports, which is not the same as what announcing returned:
  /// the wait for the echo is deliberately short, so it can time out while the
  /// membership is perfectly well there a moment later.
  String? roomMembershipId = '\$membership';

  @override
  String? membershipEventIdIn(matrix.Room room) =>
      _retracted ? null : roomMembershipId;

  @override
  Future<String?> announce() async {
    trace('announce');
    if (holdAnnounce != null) await holdAnnounce!.future;
    if (announceError != null) throw announceError!;
    return membershipId;
  }

  String? membershipId = '\$membership';

  @override
  Future<bool> retract() async {
    trace('retract');
    _retracted = true;
    if (retractError != null) throw retractError!;
    return !retractFails;
  }
}

class FakeMedia extends CallMedia {
  final Trace trace;
  Object? connectError;
  bool hasTrack;
  Object? disposeError;

  FakeMedia(this.trace, {this.hasTrack = true});

  /// Held open to reproduce a hangup landing mid-connect.
  Future<void>? beforeConnect;

  @override
  Future<void> connect(CallToken grant, {required bool video}) async {
    if (beforeConnect != null) await beforeConnect;
    trace('connect(video: $video)');
    if (connectError != null) throw connectError!;
  }

  final _track = FakeTrack();

  /// Supplied by the test rather than built from a live connection.
  FakeRoster? fakeRoster;

  @override
  CallRoster roster({required String myUserId}) => fakeRoster!;

  @override
  AudioTrack? get publishedAudio => hasTrack ? _track : null;

  @override
  Future<void> dispose() async {
    trace('media.dispose');
    if (disposeError != null) throw disposeError!;
  }
}

class FakeCapture extends CallCaptureService {
  final Trace trace;
  Object? stopError;
  Object? startError;
  Completer<void>? holdStop;
  Completer<void>? holdStart;
  FakeCapture(this.trace) : super(sink: _NullSink());

  /// Modelled, not assumed. The recorder reads this back after starting to
  /// learn whether a tap actually attached, so a double that ignored it would
  /// hide exactly the case that reading it exists to catch.
  bool _recording = false;

  /// A device with no point to record from: starting succeeds, and nothing is
  /// recording afterwards.
  bool attachesNothing = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> start(covariant Object track) async {
    trace('capture.start');
    if (holdStart != null) await holdStart!.future;
    if (startError != null) throw startError!;
    _recording = !attachesNothing;
  }

  @override
  Future<void> stop() async {
    // Silent when there is nothing to stop, as the real one is. Tracing it
    // regardless made teardown look like it was stopping a recording that had
    // never started.
    if (!_recording) return;
    trace('capture.stop');
    _recording = false;
    if (holdStop != null) await holdStop!.future;
    if (stopError != null) throw stopError!;
  }

  @override
  Future<void> finish() async {
    await stop();
    trace('capture.finish');
  }
}

/// The SFU's participant list, without an SFU.
///
/// Overrides only the two reads that need a live connection, so everything the
/// real roster decides — who is a peer, who is a sibling device, and the freeze
/// while disconnected — is the code under test rather than a stub.
class FakeRoster extends CallRoster {
  FakeRoster({required super.room, required super.myUserId});

  Set<String> identities = {};
  bool connected = true;
  bool disposed = false;

  /// Modelled because the two ways of not being connected mean opposite things:
  /// while the connection is coming back the roster holds its last picture, and
  /// once it has gone for good it clears. A double with only one of them turned
  /// a reconnect into everybody hanging up.
  bool recovering = false;

  @override
  Iterable<String> get remoteIdentities => identities;

  @override
  bool get roomConnected => connected;

  @override
  bool get roomRecovering => !connected && recovering;

  @override
  void recompute() {
    // A disposed roster is detached from its room and notifies nobody. Pinning
    // it here means a teardown that forgot to dispose shows up as a test that
    // keeps receiving presence after the call ended.
    if (disposed) return;
    super.recompute();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// Only [addAudioRenderer] is ever reached, and the recorder is faked here, so
/// nothing on this needs a real implementation.
class FakeTrack implements AudioTrack {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NullSink implements CallAudioSink {
  @override
  Future<void> deliver(PcmChunk chunk, {Duration? within}) async {}
  @override
  Future<void> close() async {}
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Trace trace;

  /// Logged in, because the recording election ranks this device against its
  /// siblings by device id and a client that never logged in has none.
  Future<Client> bareClient() async {
    final client = Client(
      'active-call-test',
      httpClient: FakeMatrixApi(),
      database: await MatrixSdkDatabase.init(
        'active-call-test',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    await client.login(
      LoginType.mLoginPassword,
      token: 'abcd',
      identifier: AuthenticationUserIdentifier(
        user: '@test:fakeServer.notExisting',
      ),
      deviceId: 'GHTYAJCE',
    );
    return client;
  }

  setUp(() => trace = Trace());

  Future<(ActiveCall, FakeCalls, FakeMedia, FakeCapture)> build({
    bool hasTrack = true,
  }) async {
    final calls = FakeCalls(await bareClient(), trace);
    final media = FakeMedia(trace, hasTrack: hasTrack);
    final capture = FakeCapture(trace);
    final roster = FakeRoster(
      room: media.room,
      myUserId: calls.client.userID ?? '',
    );
    media.fakeRoster = roster;
    calls.roster = roster;
    return (
      ActiveCall(calls: calls, media: media, capture: capture),
      calls,
      media,
      capture,
    );
  }

  matrix.Room roomStub(Client c) => matrix.Room(id: '!r:server', client: c);

  group('how long the call is recorded as having lasted', () {
    test('does not charge the conversation for its own teardown', () async {
      final (call, calls, _, capture) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      expect(call.hadPeer, isTrue);

      // Teardown held open, standing in for the flush, the upload and the wait
      // for a transcript that follow a real hangup.
      final teardown = Completer<void>();
      capture.holdStop = teardown;
      final ending = call.hangUp();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      teardown.complete();
      await ending;

      // The window closed when the call was asked to end. Measured after
      // teardown instead, this reads at least the 60ms the flush was held for.
      expect(call.talkDuration, lessThan(const Duration(milliseconds: 60)));
    });

    test('counts a peer who arrived and left before the stage moved', () async {
      final (call, calls, media, _) = await build();
      // Present before this device even looks: the ordinary case for whoever
      // answers, since the caller is already in the room.
      calls.remotePresent = true;
      // Held at the announce so the call cannot reach connected, and they leave
      // inside that window — somebody was genuinely on the call, but the stage
      // never moved.
      final announce = Completer<void>();
      calls.holdAnnounce = announce;
      final starting = call.start(
        roomStub(calls.client),
        video: false,
        answering: true,
      );
      await Future<void>.delayed(Duration.zero);
      calls.remotePresent = false;
      announce.complete();
      await starting;

      // They were here, so this was a conversation and not a missed call —
      // and it has to have lasted something, or it is written as answered with
      // nothing in it.
      expect(call.hadPeer, isTrue);
      expect(call.talkStartedAt, isNotNull);
      expect(call.talkDuration, greaterThan(Duration.zero));
      expect(media, isNotNull);
    });

    test('a call nobody answered lasted no time at all', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      await call.hangUp();
      expect(call.hadPeer, isFalse);
      expect(call.talkStartedAt, isNull);
      expect(call.talkDuration, Duration.zero);
    });
  });

  group('what is recorded, and from when', () {
    test('nothing is recorded while the call is still ringing', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      // Their phone is ringing. Anything said here is said to nobody, and
      // crediting it to the call would put words in an analytics record that
      // no learner ever heard.
      expect(trace.steps, isNot(contains('capture.start')));
    });

    test('recording begins when they answer', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      calls.remotePresent = true;
      await Future<void>.delayed(Duration.zero);
      expect(trace.steps, contains('capture.start'));
    });

    test('whoever answers records from the first word', () async {
      final (call, calls, _, _) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false, answering: true);
      // The caller is already there, so there is no waiting for an arrival that
      // has already happened — the roster is read rather than listened for.
      expect(trace.steps, contains('capture.start'));
    });
  });

  group('a connection that drops mid-call', () {
    test('stops recording, and starts again when it comes back', () async {
      final (call, calls, media, _) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue);

      // The roster deliberately holds its last picture across a reconnect, so
      // they still read as present — but nothing this learner says is reaching
      // them, and none of it should be credited as call speech.
      media.fakeRoster!.connected = false;
      media.fakeRoster!.recovering = true;
      media.fakeRoster!.recompute();
      await pumpEventQueue();
      expect(
        call.isRecording,
        isFalse,
        reason: 'words that went nowhere are not part of the conversation',
      );

      media.fakeRoster!.connected = true;
      media.fakeRoster!.recovering = false;
      media.fakeRoster!.recompute();
      await pumpEventQueue();
      expect(call.isRecording, isTrue, reason: 'and it picks back up');
    });
  });

  group('waiting for an answer', () {
    test('does not start the clock before they have been rung', () async {
      final (call, calls, _, _) = await build();
      calls.holdRing = Completer<void>();
      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();

      // Their phone has not rung yet, so there is nothing to be waiting on.
      // Started earlier, the caller's patience was spent on announcing and
      // ringing — on a slow network it could give up and write a missed call
      // while the callee was still being asked.
      await call.waitForPeerTimeoutForTest();
      expect(
        call.stage,
        isNot(CallStage.ended),
        reason: 'nobody has been asked yet, so nobody has failed to answer',
      );

      calls.holdRing!.complete();
      await starting;
      await call.waitForPeerTimeoutForTest();
      expect(call.stage, CallStage.ended, reason: 'and now it is running');
    });
  });

  group('bringing a call up', () {
    test('placing into an empty call rings the other side', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      expect(trace.steps, contains('ring'));
      expect(call.placedCall, isTrue);
    });

    test('a stale membership cannot silence a new call', () async {
      // Placing is decided by who is actually in the call, per the SFU. Matrix
      // membership is not consulted at all — it holds a crashed peer's entry
      // for around twelve minutes, and reading it would send a genuine new call
      // out silent.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      expect(trace.steps, contains('ring'));
    });

    test(
      'this account own second device joining does not ring again',
      () async {
        // The caller's second device is a different device of the same user.
        // Anyone already in the call — peer or sibling — means this is a join.
        final (call, calls, _, _) = await build();
        calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];
        await call.start(roomStub(calls.client), video: false);
        expect(trace.steps, isNot(contains('ring')));
        expect(call.placedCall, isFalse);
      },
    );

    test('a call the user ended is not reported as failed', () async {
      // Teardown running underneath a step in flight is what made it throw.
      // Reporting that as a failure showed an error for a call the user had
      // deliberately ended.
      final (call, calls, media, _) = await build();
      final gate = Completer<void>();
      media.beforeConnect = gate.future;
      media.connectError = StateError('socket closed by teardown');

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await call.hangUp();
      gate.complete();
      await starting;
      await call.settled;

      expect(call.stage, isNot(CallStage.failed));
      expect(call.stage, CallStage.ended);
    });

    test('answering never rings, even if the caller already left', () async {
      // The callee reaches the SFU after the caller gave up, so the room looks
      // empty. Deriving placing from that made the answerer ring the caller
      // back — a call nobody placed, from the wrong side.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false, answering: true);

      expect(trace.steps, isNot(contains('ring')));
      expect(
        call.placedCall,
        isFalse,
        reason: 'someone who was rung is never the one placing',
      );
    });

    test('joining an existing call does not ring the caller back', () async {
      // A call someone is already in is one this device is joining, and a ring
      // from it would ring the caller who is already there. This holds however
      // the join is reached — the banner, the header button, or a deep link.
      final (call, calls, _, _) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      expect(trace.steps, isNot(contains('ring')));
      expect(call.stage, CallStage.connected);
      expect(
        call.placedCall,
        isFalse,
        reason: 'the answering side must not also write the call to the room',
      );
    });

    test('media and recording start before the peer is told', () async {
      final (call, calls, _, _) = await build();
      // Somebody is already on the call, so this is joining one rather than
      // placing one — hence no ring — and there is somebody to record with from
      // the first moment.
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);

      // Recording is running before this device announces itself, so the peer
      // never learns we are here ahead of us being able to hear them.
      expect(trace.steps, [
        'join',
        'connect(video: false)',
        'capture.start',
        'announce',
      ]);
      expect(call.stage, CallStage.connected);
      expect(call.isRecording, isTrue);
    });

    test('video is published when asked for', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: true);
      expect(trace.steps, contains('connect(video: true)'));
    });

    test('a call with no publishable audio still connects', () async {
      // Losing analytics is worse than nothing; refusing the call is worse still.
      final (call, calls, _, _) = await build(hasTrack: false);
      await call.start(roomStub(calls.client), video: false);
      expect(call.stage, CallStage.connected);
      expect(call.isRecording, isFalse);
      expect(trace.steps, isNot(contains('capture.start')));
    });
  });

  group('a failure while coming up', () {
    test('a refused join leaves nothing behind', () async {
      final (call, calls, _, _) = await build();
      calls.joinError = StateError('no focus');
      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.failed);
      expect(call.error, isStateError);
      expect(trace.steps, [
        'join',
        'media.dispose',
        'capture.finish',
      ], reason: 'nothing was announced and no membership to retract');
    });

    test('media that will not connect retracts the join', () async {
      final (call, calls, media, _) = await build();
      media.connectError = StateError('sfu unreachable');
      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.failed);
      expect(trace.steps, [
        'join',
        'connect(video: false)',
        'retract',
        'media.dispose',
        'capture.finish',
      ]);
    });

    test('a failure to announce tears the whole call down', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.announceError = StateError('state event rejected');
      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.failed);
      expect(trace.steps, [
        'join',
        'connect(video: false)',
        'capture.start',
        'announce',
        'retract',
        'capture.stop',
        'media.dispose',
        'capture.finish',
      ], reason: 'the recording is flushed even on a failed call');
    });
  });

  group('hanging up', () {
    test('unwinds in reverse', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();
      await call.hangUp();

      expect(trace.steps, [
        'retract',
        'capture.stop',
        'media.dispose',
        'capture.finish',
      ]);
      expect(call.stage, CallStage.ended);
    });

    test('twice tears down once', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();
      await Future.wait([call.hangUp(), call.hangUp()]);
      expect(trace.steps, [
        'retract',
        'capture.stop',
        'media.dispose',
        'capture.finish',
      ]);
    });

    test('a recording that will not flush still frees the microphone '
        'and retracts the membership', () async {
      final (call, calls, _, capture) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      capture.stopError = StateError('flush failed');
      trace.steps.clear();
      await call.hangUp();

      expect(trace.steps, [
        'retract',
        'capture.stop',
        'media.dispose',
        'capture.finish',
      ]);
      expect(call.stage, CallStage.ended);
    });

    test('media that will not close does not strand the rest', () async {
      final (call, calls, media, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      media.disposeError = StateError('socket stuck');
      trace.steps.clear();
      await call.hangUp();

      expect(trace.steps, [
        'retract',
        'capture.stop',
        'media.dispose',
        'capture.finish',
      ], reason: 'a stuck socket must not strand the rest of teardown');
      expect(call.stage, CallStage.ended);
    });

    test('a retract that reports failure stays retryable', () async {
      // The service releases the session either way so calling is not blocked,
      // so a failure that did not throw would otherwise be taken for success and
      // the one retry that could help would never happen.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);

      calls.retractFails = true;
      await call.hangUp();
      expect(trace.steps, contains('retract'));

      calls.retractFails = false;
      trace.steps.clear();
      await call.hangUp();
      expect(
        trace.steps,
        contains('retract'),
        reason: 'the second hangup tries again',
      );
    });

    test('a failed retract stays retryable', () async {
      // Memoizing a teardown that could not retract would make every later
      // hangup return that same finished future, so the membership would stay
      // advertised until it expired with nothing able to take it back.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);

      calls.retractError = StateError('server refused');
      await call.hangUp();
      expect(trace.steps, contains('retract'));

      calls.retractError = null;
      trace.steps.clear();
      await call.hangUp();
      expect(
        trace.steps,
        contains('retract'),
        reason: 'the second hangup actually tries again',
      );
    });

    test('a membership that will not retract still ends the call', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      calls.retractError = StateError('server refused');
      await call.hangUp();
      expect(call.stage, CallStage.ended);
    });
  });

  test('disposing hangs up without notifying a disposed listener', () async {
    // Teardown is asynchronous, so the transition to ended lands after dispose
    // has returned. Notifying then throws — on the ordinary path of closing the
    // call screen.
    final (call, calls, _, _) = await build();
    // A call has to have somebody on it to be recorded: nothing is
    // captured while it is still ringing.
    calls.remotePresent = true;
    await call.start(roomStub(calls.client), video: false);
    trace.steps.clear();

    call.dispose();
    await pumpEventQueue();

    expect(trace.steps, [
      'retract',
      'capture.stop',
      'media.dispose',
      'capture.finish',
    ]);
    expect(call.stage, CallStage.ended);
  });

  test('the peer sees us leave before slow local cleanup runs', () async {
    // Flushing a recording waits on chunk delivery, which with a real upload
    // sink is the slowest part of hanging up. Retracting after it would leave
    // this device advertised as a participant the whole time, so the peer would
    // still see someone who had already hung up.
    final (call, calls, _, _) = await build();
    // A call has to have somebody on it to be recorded: nothing is
    // captured while it is still ringing.
    calls.remotePresent = true;
    await call.start(roomStub(calls.client), video: false);
    trace.steps.clear();

    await call.hangUp();
    expect(trace.steps.indexOf('retract'), 0);
    expect(trace.steps.indexOf('capture.stop'), greaterThan(0));
  });

  test('a hangup during connect stops the call coming up', () async {
    final (call, calls, media, _) = await build();
    final connecting = Completer<void>();
    media.beforeConnect = connecting.future;

    final starting = call.start(roomStub(calls.client), video: false);
    await pumpEventQueue();
    final hangingUp = call.hangUp();

    connecting.complete();
    await Future.wait([starting, hangingUp]);

    expect(call.stage, CallStage.ended);
    expect(
      trace.steps,
      isNot(contains('announce')),
      reason: 'a call the user abandoned must not finish assembling itself',
    );
    expect(trace.steps, contains('retract'));
  });

  group('when the other person leaves', () {
    test('the call ends rather than holding a microphone open', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      expect(call.stage, CallStage.connected);

      calls.remotePresent = false;
      await calls.participantsBecome([calls.client.deviceID!]);

      expect(call.stage, CallStage.ended);
      expect(trace.steps, contains('retract'));
    });

    test('a peer who has not answered yet does not end it', () async {
      // Their absence only means the call is over if they were ever there.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);

      await calls.participantsBecome([calls.client.deviceID!]);

      expect(call.stage, CallStage.connected, reason: 'still ringing out');
    });

    test('a peer who crashes without a leave event still ends the call', () async {
      // A membership lapses on a timer, not an event, so a crashed peer fires no
      // participant change. The periodic re-check is what notices they are gone
      // and stops holding the microphone open.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      expect(call.stage, CallStage.connected);

      // The peer's membership expires; NO participant event fires.
      calls.remotePresent = false;
      await call.tickReelectionForTest();

      expect(
        call.stage,
        CallStage.ended,
        reason: 'the periodic check caught it',
      );
    });

    test('a peer arriving then leaving ends it', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);

      calls.remotePresent = true;
      await calls.participantsBecome([calls.client.deviceID!]);
      expect(call.stage, CallStage.connected);

      calls.remotePresent = false;
      await calls.participantsBecome([calls.client.deviceID!]);
      expect(call.stage, CallStage.ended);
    });
  });

  group('when the other person declines', () {
    test('the caller stops ringing and is told why', () async {
      // Ringing at someone who has already said no is what every other calling
      // app avoids, and leaving the caller to wonder is the other half of it.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);
      expect(call.stage, CallStage.connected);

      await calls.peerDeclines();

      expect(call.stage, CallStage.declined);
      expect(call.wasDeclined, isTrue);
      expect(trace.steps, contains('retract'));
    });

    test('a decline after they answered is ignored', () async {
      // They are in the call. A stray decline event must not end a conversation
      // that is actually happening.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);

      await calls.peerDeclines();

      expect(call.stage, CallStage.connected);
      expect(call.wasDeclined, isFalse);
    });
  });

  group('when nobody is on the other end', () {
    test('the call gives up rather than waiting forever', () async {
      // Covers a callee who never answers and a caller who gave up moments
      // before this device joined. Either leaves a learner in an open call,
      // with an open microphone, and nobody there.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.connected, reason: 'still ringing out');
      await call.waitForPeerTimeoutForTest();

      expect(call.stage, CallStage.ended);
      expect(trace.steps, contains('retract'));
    });

    test('an unanswered call is not treated as a conversation', () async {
      // Reaching the SFU is not a call. Writing one would put a conversation in
      // the timeline that never happened and credit talking to nobody.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.connected);
      expect(call.hadPeer, isFalse, reason: 'nobody answered');
    });

    test('answering makes it a conversation, and says so', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);

      var notified = 0;
      call.addListener(() => notified++);

      calls.remotePresent = true;
      await calls.participantsBecome([calls.client.deviceID!]);

      expect(call.hadPeer, isTrue);
      expect(
        notified,
        greaterThan(0),
        reason: 'the stage does not change, so the screen must be told',
      );
    });

    test('answering in time stops the giving up', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);

      calls.remotePresent = true;
      await calls.participantsBecome([calls.client.deviceID!]);
      await call.waitForPeerTimeoutForTest();

      expect(call.stage, CallStage.connected, reason: 'they answered');
    });
  });

  group('which device records', () {
    test('this one, when it is alone in the call', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue);
    });

    test(
      'not this one, when a device sorting lower is already there',
      () async {
        final (call, calls, _, _) = await build();
        calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];
        await call.start(roomStub(calls.client), video: false);

        expect(call.isRecording, isFalse);
        expect(
          trace.steps,
          isNot(contains('capture.start')),
          reason: 'the other device is recording; this one would double-count',
        );
      },
    );

    test('this one takes over when the other device leaves', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isFalse);

      await calls.participantsBecome([calls.client.deviceID!]);
      expect(call.isRecording, isTrue, reason: 'it is alone now');
      expect(trace.steps, contains('capture.start'));
    });

    test('this one stops when a device sorting lower arrives', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue);
      trace.steps.clear();

      await calls.participantsBecome(['AAAAAAAAAA', calls.client.deviceID!]);
      expect(call.isRecording, isFalse);
      expect(
        trace.steps,
        contains('capture.stop'),
        reason: 'and what was already said is flushed, not dropped',
      );
    });

    test('a device sorting higher does not displace this one', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();

      await calls.participantsBecome(['zzzzzzzzzz', calls.client.deviceID!]);
      expect(call.isRecording, isTrue);
      expect(trace.steps, isNot(contains('capture.stop')));
    });

    test('a recorder that will not start does not fail the call', () async {
      // Recording is not the call. A tap that cannot open costs analytics; it
      // must never stop someone placing a voice call.
      final (call, calls, _, capture) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      capture.startError = StateError('no renderer available');

      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.connected);
      expect(trace.steps, contains('announce'));
    });

    test('a handover is not overtaken by the one before it', () async {
      // A device can be displaced and reinstated faster than a flush completes.
      // Starting the new recording while the old stop is still unwinding would
      // let that stop cancel the new tap and close its sink underneath it.
      final (call, calls, _, capture) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();

      capture.holdStop = Completer<void>();
      await calls.participantsBecome(['AAAAAAAAAA', calls.client.deviceID!]);
      await calls.participantsBecome([calls.client.deviceID!]);

      expect(trace.steps, [
        'capture.stop',
      ], reason: 'the restart waits for the stop it follows');

      capture.holdStop!.complete();
      await pumpEventQueue();
      expect(trace.steps, ['capture.stop', 'capture.start']);
    });

    test('hanging up waits for a flush already in progress', () async {
      // A device displaced moments before the hangup has a stop still unwinding
      // while it no longer counts as capturing. Finishing teardown then would
      // let the call be written before the last words were transcribed.
      final (call, calls, _, capture) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);

      capture.holdStop = Completer<void>();
      await calls.participantsBecome(['AAAAAAAAAA', calls.client.deviceID!]);

      var torn = false;
      final hangingUp = call.hangUp().then((_) => torn = true);
      await pumpEventQueue();
      expect(torn, isFalse, reason: 'teardown is waiting on the flush');

      capture.holdStop!.complete();
      await hangingUp;
      expect(torn, isTrue);
    });

    test('a start that threw is retried by the next election', () async {
      // Recording state must follow what actually happened, not what was
      // intended, or a failed tap is remembered as open and never reattempted.
      final (call, calls, _, capture) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      capture.startError = StateError('no renderer');
      await call.start(roomStub(calls.client), video: false);

      expect(call.isRecording, isFalse, reason: 'it did not actually start');

      capture.startError = null;
      trace.steps.clear();
      await calls.participantsBecome([calls.client.deviceID!, 'zzzzzzzzzz']);
      expect(trace.steps, contains('capture.start'));
      expect(call.isRecording, isTrue);
    });

    test('a phantom sibling is dropped by the periodic re-election', () async {
      // A sibling device that crashed leaves a membership that lapses on a
      // timer, not an event. This device deferred to it; the periodic tick is
      // what lets it notice the phantom is gone and take over recording.
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isFalse, reason: 'deferred to the lower id');

      // The phantom expires and leaves room state.
      calls.devicesInCall = [calls.client.deviceID!];
      await call.tickReelectionForTest();

      expect(call.isRecording, isTrue, reason: 'it took over');
    });

    test('participant changes after hangup are ignored', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      await call.hangUp();
      trace.steps.clear();

      await calls.participantsBecome(['AAAAAAAAAA']);
      expect(trace.steps, isEmpty, reason: 'the call is over');
    });
  });

  test('notifies listeners as the stage changes', () async {
    final (call, calls, _, _) = await build();
    var notifications = 0;
    call.addListener(() => notifications++);
    await call.start(roomStub(calls.client), video: false);
    await call.hangUp();
    expect(notifications, 2, reason: 'connected, then ended');
  });
  group('a hangup landing while the call is still coming up', () {
    test('does not report the call connected after it was torn down', () async {
      // start() checks for a hangup after every await for a reason: without the
      // check after ringing, teardown runs, then start() resumes and moves the
      // stage to connected. The screen then shows a live call that no longer
      // exists, and the microphone is already released.
      final (call, calls, _, _) = await build();
      final held = Completer<void>();
      calls.holdRing = held;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();

      await call.hangUp();
      held.complete();
      await starting;

      expect(call.stage, isNot(CallStage.connecting));
      expect(
        call.stage,
        anyOf(CallStage.ended, CallStage.declined),
        reason: 'a torn-down call must not come back as connected',
      );
    });

    test('leaves nothing subscribed for a decline', () async {
      // Teardown cancels the decline subscription, then start() resumed and
      // made a NEW one — after the only thing that could cancel it had already
      // run. It then outlived the call for the lifetime of the client.
      final (call, calls, _, _) = await build();
      final held = Completer<void>();
      calls.holdRing = held;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await call.hangUp();
      held.complete();
      await starting;
      await pumpEventQueue();

      expect(
        calls.watchingForDeclines,
        isFalse,
        reason: 'an abandoned call must leave nothing subscribed',
      );
    });

    test('a decline that beats the ring home is not lost', () async {
      // The subscription is older than the id it matches, so a decline can
      // arrive while our own send is still returning. Dropping it left the
      // caller ringing at someone who had already turned them down.
      final (call, calls, _, _) = await build();
      final held = Completer<void>();
      calls.holdRing = held;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      // Turned down before ring() has even returned.
      await calls.peerDeclines();
      held.complete();
      await starting;
      await call.settled;

      expect(call.wasDeclined, isTrue);
      expect(call.stage, CallStage.declined);
    });

    test('still remembers that the other side was rung', () async {
      // Their phone rang. A hangup a moment later must still leave a record —
      // otherwise a call someone saw and missed leaves no trace at all.
      final (call, calls, _, _) = await build();
      final held = Completer<void>();
      calls.holdRing = held;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      final hangingUp = call.hangUp();
      held.complete();
      await starting;
      await hangingUp;

      expect(call.notificationEventId, isNotNull);
    });

    test('a call joined with no ring can still be credited', () async {
      // Neither rang nor was rung — a device joining a call already under way.
      // Its membership is the only event in the room it can anchor to, and
      // without it every word its learner spoke went uncredited.
      final (call, calls, _, _) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);

      expect(call.placedCall, isFalse);
      expect(call.notificationEventId, isNull);
      expect(call.membershipEventId, isNotNull);
    });
  });
  group('a hangup during the LAST step of coming up', () {
    test('abandons rather than reporting the call connected', () async {
      // The final step is the one a missing guard actually shows up in: every
      // earlier step is masked by the NEXT step's check, so only here can an
      // unguarded await let a torn-down call report itself connected.
      final (call, calls, _, capture) = await build();
      final ringGate = Completer<void>();
      final stopGate = Completer<void>();
      calls.holdRing = ringGate;
      capture.holdStop = stopGate;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();

      // A sibling that outranks us appears, so the election queues a handover
      // that the final step will wait on.
      calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];
      await pumpEventQueue();
      ringGate.complete();
      await pumpEventQueue();

      // Every stage this call ever reports. Asserting only the final one cannot
      // see the defect: the hangup's own transition to ended lands afterwards
      // and overwrites it, so a call that briefly announced itself connected
      // looks identical to one that never did.
      final seen = <CallStage>[];
      call.addListener(() => seen.add(call.stage));

      // Now the hangup lands, with only the final await left to catch it.
      final hangingUp = call.hangUp();
      stopGate.complete();
      await starting;
      await hangingUp;

      expect(
        seen,
        isNot(contains(CallStage.connected)),
        reason:
            'a torn-down call must never report itself connected, even once',
      );
      expect(call.stage, CallStage.ended);
    });
  });

  group('a hangup during any step of coming up', () {
    // Coming up is a sequence of network round-trips and a hangup can land
    // inside any of them. Every step must abandon the call, and this covers
    // them ALL rather than the one a review happened to name — a step added
    // later that forgets the guard fails here.
    for (final step in const ['join', 'connect', 'announce', 'ring']) {
      test('a hangup during $step abandons the call', () async {
        final (call, calls, media, _) = await build();
        final gate = Completer<void>();
        switch (step) {
          case 'join':
            calls.holdJoin = gate;
          case 'connect':
            media.beforeConnect = gate.future;
          case 'announce':
            calls.holdAnnounce = gate;
          case 'ring':
            calls.holdRing = gate;
        }

        final starting = call.start(roomStub(calls.client), video: false);
        await pumpEventQueue();
        final hangingUp = call.hangUp();
        gate.complete();
        await starting;
        await hangingUp;

        expect(
          call.stage,
          CallStage.ended,
          reason: 'a hangup during $step must abandon, not connect or fail',
        );
      });
    }
  });
  group('when both people call at the same moment', () {
    test('a caller alone does not think the peer also called', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      expect(call.placedCall, isTrue);
      expect(call.peerAlsoPlaced, isFalse);
    });

    test('the peer ringing us while we ring them is noticed', () async {
      // Both then believe they placed the call, so both would write it to the
      // room. Noticing it is what lets exactly one of them do so — and noticing
      // it from their ring rather than from an ordering keeps a call nobody
      // answered written, since only the caller runs that teardown.
      final (call, calls, _, _) = await build();
      final ringGate = Completer<void>();
      calls.holdRing = ringGate;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await calls.peerAlsoCalls();
      ringGate.complete();
      await starting;

      expect(call.placedCall, isTrue);
      expect(call.peerAlsoPlaced, isTrue);
    });

    test('a ring after they joined is some other call, not this one', () async {
      // They are in the call, so they are not ringing us. Counting it made this
      // side believe the other had also placed this call; the write is then
      // settled by comparing ids, and the side that actually placed it can end
      // up standing aside — so nobody writes it and the call is missing from
      // the conversation.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      calls.remotePresent = true;
      await pumpEventQueue();
      expect(call.hadPeer, isTrue);

      await calls.peerAlsoCalls();
      expect(call.peerAlsoPlaced, isFalse);
    });

    test('an old call of theirs is not somebody calling now', () async {
      // Sync replays events. Counting a stale one would make this side stand
      // aside from writing the call, while the other side — not in a call at
      // all — never writes it either, and the call would vanish.
      final (call, calls, _, _) = await build();
      final ringGate = Completer<void>();
      calls.holdRing = ringGate;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await calls.peerAlsoCalls(age: const Duration(hours: 1));
      ringGate.complete();
      await starting;

      expect(call.peerAlsoPlaced, isFalse);
    });
  });
  group('when both people call at the same moment', () {
    test('a caller alone does not think the peer also called', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      expect(call.placedCall, isTrue);
      expect(call.peerAlsoPlaced, isFalse);
    });

    test('the peer ringing us while we ring them is noticed', () async {
      // Both then believe they placed the call, so both would write it to the
      // room. Noticing it is what lets exactly one of them do so — and noticing
      // it from their ring rather than from an ordering keeps a call nobody
      // answered written, since only the caller runs that teardown.
      final (call, calls, _, _) = await build();
      final ringGate = Completer<void>();
      calls.holdRing = ringGate;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await calls.peerAlsoCalls();
      ringGate.complete();
      await starting;

      expect(call.placedCall, isTrue);
      expect(call.peerAlsoPlaced, isTrue);
    });
  });
  group('a device where no tap could be attached', () {
    test('is tried again by the next election', () async {
      // Starting succeeds and records nothing — no point to read from, or the
      // platform side not up yet. Treating that as recording would stop every
      // later election from trying, and the call would go uncredited for a
      // failure that may have been momentary.
      final (call, calls, _, capture) = await build();
      capture.attachesNothing = true;
      await call.start(roomStub(calls.client), video: false);

      final first = trace.steps.where((s) => s == 'capture.start').length;
      capture.attachesNothing = false;
      // A real change to who is in the call, so an election actually runs.
      calls.remotePresent = true;
      await pumpEventQueue();

      expect(
        trace.steps.where((s) => s == 'capture.start').length,
        greaterThan(first),
        reason: 'a tap that did not attach must be attempted again',
      );
      expect(call.isRecording, isTrue);
    });
  });
  group('a peer who leaves while the call is still coming up', () {
    test('is still remembered as having been there', () async {
      // Someone already here can go while the first handover settles. Reading
      // their presence afterwards had this call believe nobody ever answered —
      // no teardown when they left, and the conversation recorded as unanswered.
      final (call, calls, _, capture) = await build();
      calls.remotePresent = true;
      // Hold the first handover open, which is the window this is about.
      final handover = Completer<void>();
      capture.holdStart = handover;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      // They go while the first handover is still settling.
      calls.remotePresent = false;
      handover.complete();
      await starting;
      await call.settled;

      expect(
        call.hadPeer,
        isTrue,
        reason: 'they were here, so the call was answered',
      );
    });
  });

  group('when the microphone is released', () {
    test('before anything waits on uploads or transcription', () async {
      // Finishing waits for what has been recorded to be sent and transcribed,
      // which can take a minute. Holding the devices through that meant the
      // learner hung up and was still being heard.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();
      await call.hangUp();

      expect(
        trace.steps.indexOf('media.dispose'),
        lessThan(trace.steps.indexOf('capture.finish')),
        reason: 'the microphone goes first; sending audio does not need one',
      );
    });
  });

  group('a hangup landing the instant a join returns', () {
    test('still gives the call back', () async {
      // The service holds the call from the moment joining returns. Giving up
      // without writing that down skipped the retract, and the service then
      // believed it was still in a call and refused every later one — the
      // learner could not call again at all.
      final (call, calls, _, _) = await build();
      final joinGate = Completer<void>();
      calls.holdJoin = joinGate;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      final hangingUp = call.hangUp();
      joinGate.complete();
      await starting;
      await hangingUp;

      expect(
        trace.steps,
        contains('retract'),
        reason: 'a call that was joined must always be given back',
      );
    });
  });

  group('the anchor a joining device credits its speech to', () {
    test('is read before the call is given up, not after', () async {
      // Retracting releases what identifies the call, and the membership can no
      // longer be matched to it afterwards — which is exactly the device that
      // needs it: one that joined a call already under way and so has no ring of
      // its own to point at.
      final (call, calls, _, _) = await build();
      calls.remotePresent = true;
      // The echo did not arrive in time, so announcing returned nothing — the
      // case the late read exists for.
      calls.membershipId = null;
      await call.start(roomStub(calls.client), video: false);
      await call.hangUp();

      expect(call.placedCall, isFalse);
      expect(call.notificationEventId, isNull);
      expect(
        call.membershipEventId,
        isNotNull,
        reason: 'without this the whole call goes uncredited',
      );
    });
  });

  group('a ring arriving before our media is up', () {
    test('still counts as the two of us calling at once', () async {
      // The window starts when our call does, not when our media happens to be
      // ready. Watching only from there let a simultaneous call through, and
      // both sides would write the call to the room.
      final (call, calls, media, _) = await build();
      final connecting = Completer<void>();
      media.beforeConnect = connecting.future;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await calls.peerAlsoCalls();
      connecting.complete();
      await starting;

      expect(call.peerAlsoPlaced, isTrue);
    });
  });
  group('a decline replayed out of the room history', () {
    test('does not end a call that has only just started', () async {
      // Sync replays events. A decline from an earlier call arriving as this one
      // begins would end it on the spot, and the learner would watch their call
      // hang up by itself.
      final (call, calls, _, _) = await build();
      final ringGate = Completer<void>();
      calls.holdRing = ringGate;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await calls.peerDeclinedLongAgo();
      ringGate.complete();
      await starting;
      await call.settled;

      expect(call.wasDeclined, isFalse);
      expect(call.stage, CallStage.connected);
    });
  });
}

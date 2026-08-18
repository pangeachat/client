import 'package:flutter_test/flutter_test.dart';

import 'package:livekit_client/livekit_client.dart' show AudioTrack;
import 'package:matrix/matrix.dart' hide Room;
import 'package:matrix/matrix.dart' as matrix show Room;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';

/// Records the order every step ran in, which is the property under test: the
/// call comes up in one order and down in the reverse, and the failure paths
/// have to preserve that.
class Trace {
  final List<String> steps = [];
  void call(String step) => steps.add(step);
}

class FakeCalls extends CallService {
  final Trace trace;
  Object? joinError;
  Object? announceError;
  Object? retractError;

  FakeCalls(super.client, this.trace);

  @override
  Future<CallToken> join(matrix.Room room) async {
    trace('join');
    if (joinError != null) throw joinError!;
    return const CallToken(jwt: 'jwt', url: 'ws://sfu');
  }

  @override
  Future<void> announce() async {
    trace('announce');
    if (announceError != null) throw announceError!;
  }

  @override
  Future<void> retract() async {
    trace('retract');
    if (retractError != null) throw retractError!;
  }
}

class FakeMedia extends CallMedia {
  final Trace trace;
  Object? connectError;
  bool hasTrack;
  Object? disposeError;

  FakeMedia(this.trace, {this.hasTrack = true});

  @override
  Future<void> connect(CallToken grant, {required bool video}) async {
    trace('connect(video: $video)');
    if (connectError != null) throw connectError!;
  }

  final _track = FakeTrack();

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
  FakeCapture(this.trace) : super(sink: _NullSink());

  @override
  void start(covariant Object track) => trace('capture.start');

  @override
  Future<void> stop() async {
    trace('capture.stop');
    if (stopError != null) throw stopError!;
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
  Future<void> deliver(PcmChunk chunk) async {}
  @override
  Future<void> close() async {}
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Trace trace;

  Future<Client> bareClient() async => Client(
    'active-call-test',
    httpClient: FakeMatrixApi(),
    database: await MatrixSdkDatabase.init(
      'active-call-test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    ),
  );

  setUp(() => trace = Trace());

  Future<(ActiveCall, FakeCalls, FakeMedia, FakeCapture)> build({
    bool hasTrack = true,
  }) async {
    final calls = FakeCalls(await bareClient(), trace);
    final media = FakeMedia(trace, hasTrack: hasTrack);
    final capture = FakeCapture(trace);
    return (
      ActiveCall(calls: calls, media: media, capture: capture),
      calls,
      media,
      capture,
    );
  }

  matrix.Room roomStub(Client c) => matrix.Room(id: '!r:server', client: c);

  group('bringing a call up', () {
    test('media and recording start before the peer is told', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);

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
        'media.dispose',
        'retract',
      ]);
    });

    test('a failure to announce tears the whole call down', () async {
      final (call, calls, _, _) = await build();
      calls.announceError = StateError('state event rejected');
      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.failed);
      expect(trace.steps, [
        'join',
        'connect(video: false)',
        'capture.start',
        'announce',
        'capture.stop',
        'media.dispose',
        'retract',
      ], reason: 'the recording is flushed even on a failed call');
    });
  });

  group('hanging up', () {
    test('unwinds in reverse', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();
      await call.hangUp();

      expect(trace.steps, ['capture.stop', 'media.dispose', 'retract']);
      expect(call.stage, CallStage.ended);
    });

    test('twice tears down once', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();
      await Future.wait([call.hangUp(), call.hangUp()]);
      expect(trace.steps, ['capture.stop', 'media.dispose', 'retract']);
    });

    test('a recording that will not flush still frees the microphone '
        'and retracts the membership', () async {
      final (call, calls, _, capture) = await build();
      await call.start(roomStub(calls.client), video: false);
      capture.stopError = StateError('flush failed');
      trace.steps.clear();
      await call.hangUp();

      expect(trace.steps, ['capture.stop', 'media.dispose', 'retract']);
      expect(call.stage, CallStage.ended);
    });

    test('media that will not close still retracts the membership', () async {
      final (call, calls, media, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      media.disposeError = StateError('socket stuck');
      trace.steps.clear();
      await call.hangUp();

      expect(
        trace.steps,
        ['capture.stop', 'media.dispose', 'retract'],
        reason: 'a stuck socket must not advertise us in a call we have left',
      );
      expect(call.stage, CallStage.ended);
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
    await call.start(roomStub(calls.client), video: false);
    trace.steps.clear();

    call.dispose();
    await pumpEventQueue();

    expect(trace.steps, ['capture.stop', 'media.dispose', 'retract']);
    expect(call.stage, CallStage.ended);
  });

  test('notifies listeners as the stage changes', () async {
    final (call, calls, _, _) = await build();
    var notifications = 0;
    call.addListener(() => notifications++);
    await call.start(roomStub(calls.client), video: false);
    await call.hangUp();
    expect(notifications, 2, reason: 'connected, then ended');
  });
}

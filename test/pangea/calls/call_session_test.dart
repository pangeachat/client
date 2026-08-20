import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_roster.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_session.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// The narrowest fakes a session needs: a service whose join answers, media
/// that never touches the network, capture that records nothing.
class _FakeCalls extends CallService {
  _FakeCalls(super.client);

  bool retracted = false;

  @override
  int get joinAttempt => 0;

  @override
  Future<CallToken> join(matrix.Room room) async =>
      const CallToken(jwt: 'jwt', url: 'ws://sfu');

  @override
  Future<String?> announce() async => '\$membership';

  @override
  String? membershipEventIdIn(matrix.Room room) => '\$membership';

  @override
  Future<bool> retract() async {
    retracted = true;
    return true;
  }

  @override
  Future<String?> ring(
    matrix.Room room, {
    required String membershipEventId,
    required bool video,
  }) async => '\$notification';

  @override
  Stream<matrix.Event> ringsIn(matrix.Room room) => const Stream.empty();

  @override
  Stream<matrix.Event> declinesIn(matrix.Room room) => const Stream.empty();

  @override
  String? declineTarget(matrix.Event event) => null;

  @override
  void abandonJoin(int attempt) {}
}

class _FakeRoster extends CallRoster {
  _FakeRoster({required super.room, required super.myUserId});

  Set<String> identities = {};
  bool connected = true;

  @override
  Iterable<String> get remoteIdentities => identities;

  @override
  bool get roomConnected => connected;
}

class _FakeMedia extends CallMedia {
  _FakeRoster? fakeRoster;

  @override
  Future<void> connect(CallToken grant, {required bool video}) async {}

  @override
  lk.AudioTrack? get publishedAudio => null;

  @override
  CallRoster roster({required String myUserId}) =>
      fakeRoster ??= _FakeRoster(room: room, myUserId: myUserId);

  @override
  Future<void> setMicrophoneEnabled(bool on) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}

class _NullSink implements CallAudioSink {
  @override
  Future<void> deliver(PcmChunk chunk, {Duration? within}) async {}

  @override
  Future<void> close() async {}
}

Future<matrix.Client> _bareClient() async {
  final client = matrix.Client(
    'call-session-test',
    httpClient: matrix.FakeMatrixApi(),
    database: await matrix.MatrixSdkDatabase.init(
      'call-session-test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    ),
  );
  await client.login(
    matrix.LoginType.mLoginPassword,
    token: 'abcd',
    identifier: matrix.AuthenticationUserIdentifier(
      user: '@test:fakeServer.notExisting',
    ),
    deviceId: 'GHTYAJCE',
  );
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(CallSession, _FakeCalls, List<CallSession>)> build() async {
    final client = await _bareClient();
    final calls = _FakeCalls(client);
    final released = <CallSession>[];
    final session = CallSession.start(
      room: matrix.Room(id: '!r:server', client: client),
      video: false,
      callService: calls,
      transcribe: (request) async =>
          SpeechToTextResponseModel(results: const []),
      userL1: 'en',
      userL2: 'es',
      analytics: (eventId, uses, language) async {},
      onReleased: released.add,
      mediaOverride: _FakeMedia(),
      captureOverride: CallCaptureService(sink: _NullSink()),
    );
    await pumpEventQueue();
    return (session, calls, released);
  }

  test('minimize, expand and fullscreen notify without overflowing', () async {
    // A blanket edit once made the session's notify helper call itself, and
    // nothing noticed because nothing constructed a session. This is the
    // cheapest construction that exercises every UI-state notification.
    final (session, _, _) = await build();
    var notified = 0;
    session.addListener(() => notified++);

    session.minimize();
    expect(session.minimized, isTrue);
    session.expand();
    expect(session.minimized, isFalse);
    session.toggleFullscreen();
    expect(session.fullscreen, isTrue);
    session.minimize();
    expect(session.fullscreen, isFalse, reason: 'minimizing exits fullscreen');
    expect(notified, 4);

    session.attachPresenter();
    expect(session.hasPresenter, isTrue);
    session.detachPresenter();
    expect(session.hasPresenter, isFalse);
    expect(notified, 6);
    session.endCall();
  });

  test('ending releases the session exactly once, immediately', () async {
    final (session, _, released) = await build();
    session.endCall();
    expect(session.isOver, isTrue, reason: 'the outcome latch is immediate');
    expect(released, [session]);
  });

  test('a view detaching after disposal is absorbed, not a crash', () async {
    final (session, _, released) = await build();
    session.attachPresenter();
    session.endCall();
    expect(released, [session]);
    session.dispose();
    // The global tile and chat host detach on unmount, which happens AFTER the
    // holder disposed the session on the ordinary path of a call ending.
    session.detachPresenter();
  });
}

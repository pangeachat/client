import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/call_roster.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_session.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/calls/call_upload_gate.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

import 'package:pangea_call_capture/pangea_call_capture.dart'
    show CallForegroundControl;

/// The narrowest fakes a session needs: a service whose join answers, media
/// that never touches the network, capture that records nothing.
class _FakeCalls extends CallService {
  _FakeCalls(super.client);

  /// When this device's original membership was written, for a rejoin.
  DateTime? membershipWrittenAtValue;

  @override
  DateTime? membershipWrittenAt(matrix.Room room, String eventId) =>
      membershipWrittenAtValue;

  bool retracted = false;

  /// Their ring, for the case where both sides call at once.
  final _rings = StreamController<matrix.Event>.broadcast();

  @override
  Stream<matrix.Event> ringsIn(matrix.Room room) => _rings.stream;

  /// The peer calling us at the same moment we call them.
  Future<void> peerAlsoCalls(matrix.Room room) async {
    _rings.add(
      matrix.Event(
        type: PangeaEventTypes.callNotification,
        content: {
          'application': {
            'type': 'm.call',
            'notification_type': 'ring',
            'sender_ts': DateTime.now().millisecondsSinceEpoch,
            'lifetime': 30000,
          },
          'm.relates_to': {
            'rel_type': 'm.reference',
            'event_id': r'$their-membership',
          },
        },
        eventId: r'$their-ring',
        senderId: '@friend:fakeServer.notExisting',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    await pumpEventQueue();
  }

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
  Stream<matrix.Event> declinesIn(matrix.Room room) => const Stream.empty();

  @override
  String? declineTarget(matrix.Event event) => null;

  @override
  PeerPresence callerPresence(
    matrix.Room room,
    String callerId, {
    String? deviceId,
  }) => PeerPresence.live;

  @override
  void abandonJoin(int attempt) {}
}

/// A membership echo that never arrives -- not late, not ever. `announce()`
/// times out the way a slow sync or a homeserver hiccup does, and state never
/// catches up either, so the late-anchor retry ActiveCall runs in the
/// background exhausts its bounded attempts with nothing to show for them.
/// The ring this device was placing is never sent: no push goes out, and the
/// other side's phone never rings.
class _NeverEchoesCalls extends _FakeCalls {
  _NeverEchoesCalls(super.client);

  @override
  Future<String?> announce() async => null;

  @override
  String? membershipEventIdIn(matrix.Room room) => null;
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

/// Records what the session asked the timeline for. Nothing in the suite
/// checked that a finished call writes its card at all -- the record's own
/// tests cover HOW a card is written, not WHETHER the session writes one --
/// and a browser run found a completed call that left no trace.
class _SpyRecord extends CallRecord {
  _SpyRecord()
    : super(
        roomId: '!r:server',
        transcripts: CallTranscriptSink(
          transcribe: (_) async => SpeechToTextResponseModel(results: const []),
          userL1: 'en',
          userL2: 'es',
        ),
        sendEvent: (content, txid) async => '\$sent',
        analytics: (eventId, uses, language) async {},
      );

  final cards = <({bool answered, bool declined, bool write})>[];

  @override
  Future<void> writeCard({
    required Duration duration,
    required bool video,
    required bool answered,
    required bool declined,
    required bool writeTimelineEvent,
    String? anchorEventId,
    String? callerId,
    String? callKey,
  }) async {
    cards.add((
      answered: answered,
      declined: declined,
      write: writeTimelineEvent,
    ));
  }
}

class _FakeMedia extends CallMedia {
  /// A device clock the test states, so a latched anchor is exact.
  _FakeMedia({super.now});

  _FakeRoster? fakeRoster;

  /// A camera that refuses to open, as a blocked web host or a denied prompt
  /// produces: the call still comes up, on audio.
  bool refuseCamera = false;

  /// Nothing to publish through at all: the call comes up and the other side
  /// hears silence.
  bool refuseCapture = false;

  @override
  bool get captureRefused => refuseCapture;

  @override
  bool get cameraFailed => refuseCamera;

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

/// A room that records what the session puts in the timeline, so a test can
/// see the call card land without waiting on anything behind it.
class _RecordingRoom extends matrix.Room {
  _RecordingRoom({required super.id, required super.client});

  final List<Map<String, dynamic>> sent = [];
  final List<String> sentTypes = [];

  /// Only the call CARDS.
  ///
  /// A session writes more than one kind of event -- the card the conversation
  /// shows, and this device's transcript half. Assertions about what the
  /// conversation shows must say so, or adding any second event type breaks
  /// them for reasons that have nothing to do with what they are testing.
  List<Map<String, dynamic>> get cards => [
    for (var i = 0; i < sent.length; i++)
      if (sentTypes[i] == PangeaEventTypes.call) sent[i],
  ];

  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = matrix.EventTypes.Message,
    String? txid,
    matrix.Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    sent.add(content);
    sentTypes.add(type);
    return '\$card';
  }
}

/// Capture whose drain never finishes -- the shape of a call whose last chunks
/// are still in speech-to-text when the learner hangs up.
class _HangingCapture extends CallCaptureService {
  _HangingCapture() : super(sink: _NullSink());

  @override
  Future<void> finish() => Completer<void>().future;
}

/// Records what the app hands the platform to render.
class _LabelSpyForeground extends CallForegroundControl {
  const _LabelSpyForeground(this.seen);

  final List<({String mute, String channel})> seen;

  @override
  Future<int> start({
    required String peer,
    required bool video,
    required String muteLabel,
    required String channelName,
  }) async {
    seen.add((mute: muteLabel, channel: channelName));
    return 1;
  }

  @override
  Future<void> stop({required int generation}) async {}

  @override
  Future<void> setCamera(bool on, {required int generation}) async {}
}

class _NullSink implements CallAudioSink {
  @override
  Future<void> deliver(PcmChunk chunk, {Duration? within}) async {}

  @override
  Future<bool> close() async => true;
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

  // The session builds a sink on the process-wide upload gate, and one test
  // here leaves a transcription that never answers. See call_record_test.
  setUp(CallUploadGate.resetShared);

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

  test(
    'a live session actually WRITES a transcript half to the room',
    () async {
      // The feature is only real if something calls it. Everything underneath
      // was built and green while nothing in the app ever wrote a transcript:
      // CallRecord.publishTranscript was optional and no caller supplied it. A
      // suite that proves every part works and never checks the parts are
      // connected reads as a working feature and ships a dark one.
      final client = await _bareClient();
      final room = _RecordingRoom(id: '!r:server', client: client);
      // A device thirty seconds ahead of the SFU, latched at join exactly as
      // the real media does when the local participant first appears.
      final sfuJoin = DateTime.utc(2026, 8, 26, 9);
      final media = _FakeMedia(
        now: () => sfuJoin.add(const Duration(seconds: 30)),
      )..anchorClocksTo(sfuJoin);
      final session = CallSession.start(
        room: room,
        video: false,
        callService: _FakeCalls(client),
        transcribe: (request) async =>
            SpeechToTextResponseModel(results: const []),
        userL1: 'en',
        userL2: 'es',
        analytics: (eventId, uses, language) async {},
        onReleased: (_) {},
        mediaOverride: media,
        captureOverride: CallCaptureService(sink: _NullSink()),
      );
      await pumpEventQueue();

      final publish = session.transcriptPublisher;
      expect(
        publish,
        isNotNull,
        reason: 'the live call must supply a publisher, not leave it null',
      );

      await publish!(
        callKey: r'$anchor:server',
        segments: const [TranscriptSegment('hola que tal')],
        chunksCaptured: 1,
        chunksTranscribed: 1,
        chunksLost: 0,
        chunksSuppressed: 0,
        captureRefused: false,
        drainComplete: true,
        langCode: 'es',
      );

      final index = room.sentTypes.indexOf(CallTranscriptContent.relType);
      expect(
        index,
        isNonNegative,
        reason: 'the publisher must reach the room, not merely exist',
      );

      final written = room.sent[index];
      expect(written['call_key'], r'$anchor:server');
      expect(written['m.relates_to'], {
        'rel_type': CallTranscriptContent.relType,
        'event_id': r'$anchor:server',
      });
      expect((written['segments'] as List).single['text'], 'hola que tal');

      // And the join-time clock readings reach the event. This is the seam
      // between the media that latched them and the half that carries them,
      // and it is the one step the reader-side tests cannot see: without it
      // every published half is unanchored, the correction never applies, and
      // nothing else in the suite would notice.
      expect(
        CallTranscriptContent.fromJson(written)!.clockAnchor?.offsetMs,
        30000,
      );
    },
  );

  test('the call card is written at hangup, not after transcription', () async {
    // The card states the duration, who called and whether it was answered --
    // all of it known the instant the call ends. It used to be written in a
    // whenComplete on hangUp, which drains every captured chunk through
    // speech-to-text first: the card arrived 10-60s late, and was lost
    // entirely if the learner closed the tab before the last chunk came back.
    final client = await _bareClient();
    final room = _RecordingRoom(id: '!r:server', client: client);
    final neverTranscribes = Completer<SpeechToTextResponseModel>();
    final session = CallSession.start(
      room: room,
      video: false,
      callService: _FakeCalls(client),
      transcribe: (request) => neverTranscribes.future,
      userL1: 'en',
      userL2: 'es',
      analytics: (eventId, uses, language) async {},
      onReleased: (_) {},
      mediaOverride: _FakeMedia(),
      captureOverride: _HangingCapture(),
    );
    await pumpEventQueue();

    session.endCall();
    await pumpEventQueue();

    expect(
      room.cards.map((e) => e['type'] ?? 'pangea.call'),
      isNotEmpty,
      reason: 'the card must not wait for speech-to-text that may never return',
    );
    expect(neverTranscribes.isCompleted, isFalse, reason: 'still transcribing');
  });

  test('a session can be fullscreen from its first frame', () async {
    // A call answered on an account that is NOT the foregrounded one has no
    // chat pane to be shown in -- its room belongs to another account, so
    // navigating there lands on RoomUnavailablePanel. GlobalCallTile presents
    // it instead, and renders the full CallPanel only when the session is
    // fullscreen; otherwise it renders CallMiniTile, which has neither hangup
    // nor mute.
    //
    // So the flag has to travel with CONSTRUCTION. Toggling it after
    // `activeCall.value` is assigned would paint one frame of a call the
    // learner has just answered and cannot end, because that assignment is
    // what makes the tile build.
    final client = await _bareClient();
    final session = CallSession.start(
      room: matrix.Room(id: '!r:server', client: client),
      video: false,
      callService: _FakeCalls(client),
      transcribe: (request) async =>
          SpeechToTextResponseModel(results: const []),
      userL1: 'en',
      userL2: 'es',
      analytics: (eventId, uses, language) async {},
      onReleased: (_) {},
      fullscreen: true,
      mediaOverride: _FakeMedia(),
      captureOverride: CallCaptureService(sink: _NullSink()),
    );
    await pumpEventQueue();

    expect(
      session.fullscreen,
      isTrue,
      reason: 'the first frame must already be the full panel',
    );

    // And the default is unchanged, so every existing caller -- placing a
    // call, answering on the active account, returning from a rejoin offer --
    // behaves exactly as before.
    final (ordinary, _, _) = await build();
    expect(ordinary.fullscreen, isFalse);
    session.endCall();
    ordinary.endCall();
  });

  test('showing a call fullscreen twice keeps it fullscreen', () async {
    // The floating tile is the only way back to a call whose room cannot be
    // navigated to -- one on an account that is not the foregrounded one --
    // and it hands that tap to this. A TOGGLE would turn fullscreen back off
    // on a double tap, or on two callbacks arriving before the tile rebuilds,
    // dropping the learner into CallMiniTile, which has neither hangup nor
    // mute: a live call with no way to end it.
    final (session, _, _) = await build();

    session.showFullscreen();
    expect(session.fullscreen, isTrue);
    session.showFullscreen();
    expect(session.fullscreen, isTrue, reason: 'showing is not toggling');

    // And it un-minimizes, because a minimized call is not being shown.
    session.minimize();
    expect(session.fullscreen, isFalse);
    session.showFullscreen();
    expect(session.minimized, isFalse);
    expect(session.fullscreen, isTrue);
    session.endCall();
  });

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

  test(
    'ending latches immediately and hands the session over exactly once',
    () async {
      final (session, _, released) = await build();
      session.endCall();
      expect(session.isOver, isTrue, reason: 'the outcome latch is immediate');
      // The HANDOVER is deliberately not synchronous. Release runs from inside
      // the call's own listener walk, and the holder disposes the call on
      // release -- disposing a notifier mid-notification corrupts its listener
      // bookkeeping (a RangeError deep in notifyListeners, seen live). So the
      // latch is instant, the handover is a microtask later.
      expect(released, isEmpty, reason: 'not from inside the notification');
      await pumpEventQueue();
      expect(released, [session]);
    },
  );

  test('a view detaching after disposal is absorbed, not a crash', () async {
    final (session, _, released) = await build();
    session.attachPresenter();
    session.endCall();
    await pumpEventQueue();
    expect(released, [session]);
    session.dispose();
    // The global tile and chat host detach on unmount, which happens AFTER the
    // holder disposed the session on the ordinary path of a call ending.
    session.detachPresenter();
  });
  group('the survivor card', () {
    /// An ANSWERED call on the side that does not write: the ring names the
    /// caller's membership, the peer is present, and the writer -- the other
    /// side -- may or may not get its card out before dying.
    Future<(CallSession, _RecordingRoom, _FakeMedia)> answeredCall() async {
      final client = await _bareClient();
      // A DIRECT chat, so the peer resolves: the survivor names the caller.
      client.accountData['m.direct'] = matrix.BasicEvent(
        type: 'm.direct',
        content: {
          '@friend:fakeServer.notExisting': ['!r:server'],
        },
      );
      final room = _RecordingRoom(id: '!r:server', client: client);
      final media = _FakeMedia();
      final session = CallSession.start(
        room: room,
        video: false,
        callService: _FakeCalls(client),
        transcribe: (request) async =>
            SpeechToTextResponseModel(results: const []),
        userL1: 'en',
        userL2: 'es',
        analytics: (eventId, uses, language) async {},
        onReleased: (_) {},
        notificationEventId: r'$ring',
        callerMembershipEventId: r'$caller-membership',
        mediaOverride: media,
        captureOverride: CallCaptureService(sink: _NullSink()),
      );
      await pumpEventQueue();
      final roster = media.fakeRoster!;
      roster.identities = {'@friend:fakeServer.notExisting:FRIENDDEV'};
      roster.recompute();
      await pumpEventQueue();
      return (session, room, media);
    }

    // A caller whose app dies between ringing and being answered leaves a
    // membership that still reads as "calling", so a call back can look like
    // glare. If the tie-break then hands the writing to that dead device, the
    // attempt used to vanish from the conversation entirely: the survivor
    // check only ran for calls somebody had actually joined.
    test(
      'an attempt the other side was never alive to write is still written',
      () async {
        final client = await _bareClient();
        client.accountData['m.direct'] = matrix.BasicEvent(
          type: 'm.direct',
          content: {
            '@friend:fakeServer.notExisting': ['!r:server'],
          },
        );
        final room = _RecordingRoom(id: '!r:server', client: client);
        final calls = _FakeCalls(client);
        final session = CallSession.start(
          room: room,
          video: false,
          callService: calls,
          transcribe: (request) async =>
              SpeechToTextResponseModel(results: const []),
          userL1: 'en',
          userL2: 'es',
          analytics: (eventId, uses, language) async {},
          onReleased: (_) {},
          mediaOverride: _FakeMedia(),
          captureOverride: CallCaptureService(sink: _NullSink()),
        );
        await pumpEventQueue();
        // Their ring lands while we are placing ours: glare, as far as we can
        // tell. Nobody ever joins.
        await calls.peerAlsoCalls(room);
        await pumpEventQueue();
        session.timelineEventsOverride = () async => const [];
        session.endCall();
        await pumpEventQueue();

        await session.survivorCheckNowForTest();
        expect(
          room.cards,
          hasLength(1),
          reason: 'a real attempt has to leave a trace even so',
        );
      },
    );

    test('the writer dying leaves the survivor to write the card', () async {
      final (session, room, _) = await answeredCall();
      session.timelineEventsOverride = () async => const [];
      session.endCall();
      await pumpEventQueue();
      expect(room.cards, isEmpty, reason: 'the answerer never fast-writes');

      await session.survivorCheckNowForTest();

      expect(room.cards, hasLength(1), reason: 'the survivor card');
      final card = room.cards.single;
      expect(card[CallRecord.callKeyField], r'$caller-membership');
      expect(card['answered'], isTrue);
      expect(card['declined'], isFalse);
      expect(card['caller'], '@friend:fakeServer.notExisting');
    });

    test("the writer's card arriving means the survivor stays quiet", () async {
      final (session, room, _) = await answeredCall();
      final client = room.client;
      session.timelineEventsOverride = () async => [
        matrix.Event(
          type: PangeaEventTypes.call,
          content: {CallRecord.callKeyField: r'$caller-membership'},
          senderId: '@friend:fakeServer.notExisting',
          eventId: r'$their-card',
          originServerTs: DateTime.now(),
          room: matrix.Room(id: '!r:server', client: client),
        ),
      ];
      session.endCall();
      await pumpEventQueue();

      await session.survivorCheckNowForTest();

      expect(room.cards, isEmpty, reason: 'their card exists; nothing to add');
    });

    test("a stranger's card does not stop the survivor writing", () async {
      // The key is the caller's membership event id, which every room member
      // can see DURING the call. Checking only type and key let anyone post a
      // card carrying it inside the settle window: this check found it, the
      // real survivor card was never written, and the timeline then correctly
      // refused to draw the forgery -- leaving the call with no card from
      // anybody, and its transcript unreachable.
      final (session, room, _) = await answeredCall();
      final client = room.client;
      session.timelineEventsOverride = () async => [
        matrix.Event(
          type: PangeaEventTypes.call,
          content: {CallRecord.callKeyField: r'$caller-membership'},
          senderId: '@stranger:evil.example',
          eventId: r'$forged',
          originServerTs: DateTime.now(),
          room: matrix.Room(id: '!r:server', client: client),
        ),
      ];
      session.endCall();
      await pumpEventQueue();

      await session.survivorCheckNowForTest();

      expect(room.cards, hasLength(1), reason: 'the real card is written');
    });

    test('a card whose send FAILED does not stop the survivor either', () async {
      // It is kept locally and marked errored, nothing retries it, and the
      // peer never receives it -- so treating it as already written suppresses
      // the one write that would have reached them.
      final (session, room, _) = await answeredCall();
      final client = room.client;
      session.timelineEventsOverride = () async => [
        matrix.Event(
          type: PangeaEventTypes.call,
          content: {CallRecord.callKeyField: r'$caller-membership'},
          senderId: '@friend:fakeServer.notExisting',
          eventId: r'$never-sent',
          originServerTs: DateTime.now(),
          room: matrix.Room(id: '!r:server', client: client),
          status: matrix.EventStatus.error,
        ),
      ];
      session.endCall();
      await pumpEventQueue();

      await session.survivorCheckNowForTest();

      expect(room.cards, hasLength(1));
    });

    test("an unvouchable card does not stop the survivor writing", () async {
      // The other half of the same attack. This check decides whether to SKIP
      // writing the real card, so a card that cannot prove it came from a
      // party to the call must not be able to stop us -- otherwise a stranger
      // who was in the room during the call posts one carrying the key, the
      // survivor stays quiet, the timeline correctly refuses to draw the
      // forgery, and the call ends with no card from anybody.
      final (session, room, _) = await answeredCall();
      final client = room.client;
      client.accountData.remove('m.direct');
      session.timelineEventsOverride = () async => [
        matrix.Event(
          type: PangeaEventTypes.call,
          content: {CallRecord.callKeyField: r'$caller-membership'},
          senderId: '@third:server',
          eventId: r'$unvouchable',
          originServerTs: DateTime.now(),
          room: matrix.Room(id: '!r:server', client: client),
        ),
      ];
      session.endCall();
      await pumpEventQueue();

      await session.survivorCheckNowForTest();

      expect(room.cards, hasLength(1), reason: 'the real card is written');
    });

    test('a refused microphone is declared, not read as silence', () async {
      // The state a phone lands in when the browser will not grant it a
      // microphone -- exactly what the local two-device test produces. The
      // sink sees no chunks, so the half looks identical to a muted
      // speaker's, and the screen then tells the learner that somebody who
      // talked the whole call "did not say anything": a confident claim about
      // a person, sourced entirely from our own failure.
      //
      // Driven through the real hangup rather than by calling finish()
      // directly. Passing the flag in by hand proves the parameter exists and
      // nothing about whether the session fills it in, which is the part that
      // was missing.
      final (session, room, media) = await answeredCall();
      media.refuseCapture = true;
      session.timelineEventsOverride = () async => const [];
      session.endCall();
      await pumpEventQueue();

      final index = room.sentTypes.indexOf(CallTranscriptContent.relType);
      expect(index, isNonNegative, reason: 'a half was written');
      expect(
        room.sent[index]['capture_refused'],
        isTrue,
        reason: 'and it says the microphone never opened',
      );
    });

    test('an ordinary call does not claim its microphone failed', () async {
      // The counterweight: the flag must not fire on every call, or it would
      // hedge every transcript and mean nothing.
      final (session, room, _) = await answeredCall();
      session.timelineEventsOverride = () async => const [];
      session.endCall();
      await pumpEventQueue();

      final index = room.sentTypes.indexOf(CallTranscriptContent.relType);
      expect(index, isNonNegative);
      expect(room.sent[index]['capture_refused'], isFalse);
    });

    test('the survivor never invents an answered call', () async {
      // A caller whose app dies mid-ring leaves a membership that still reads
      // as calling, so a call BACK looks like glare: peerAlsoPlaced turns on,
      // the tie-break hands the writing to the dead device, and this side
      // takes the survivor path -- for a call nobody ever joined. Writing
      // that as answered puts "Voice call" in the conversation for a ring
      // that was never picked up.
      final client = await _bareClient();
      client.accountData['m.direct'] = matrix.BasicEvent(
        type: 'm.direct',
        content: {
          '@friend:fakeServer.notExisting': ['!r:server'],
        },
      );
      final room = _RecordingRoom(id: '!r:server', client: client);
      final calls = _FakeCalls(client);
      final session = CallSession.start(
        room: room,
        video: false,
        callService: calls,
        transcribe: (request) async =>
            SpeechToTextResponseModel(results: const []),
        userL1: 'en',
        userL2: 'es',
        analytics: (eventId, uses, language) async {},
        onReleased: (_) {},
        // We PLACED this one: no ring came in, so there is nothing to answer.
        notificationEventId: null,
        callerMembershipEventId: null,
        mediaOverride: _FakeMedia(),
        captureOverride: CallCaptureService(sink: _NullSink()),
      );
      await pumpEventQueue();
      await calls.peerAlsoCalls(room);
      expect(
        session.hadPeer,
        isFalse,
        reason: 'nobody ever joined; the roster stayed empty',
      );

      session.timelineEventsOverride = () async => const [];
      session.endCall();
      await pumpEventQueue();
      await session.survivorCheckNowForTest();

      expect(room.cards, hasLength(1), reason: 'the attempt is still recorded');
      expect(
        room.cards.single['answered'],
        isFalse,
        reason: 'nobody answered it, and the survivor may not pretend they did',
      );
    });

    test('a call that never had a peer schedules no survivor', () async {
      final client = await _bareClient();
      final room = _RecordingRoom(id: '!r:server', client: client);
      final session = CallSession.start(
        room: room,
        video: false,
        callService: _FakeCalls(client),
        transcribe: (request) async =>
            SpeechToTextResponseModel(results: const []),
        userL1: 'en',
        userL2: 'es',
        analytics: (eventId, uses, language) async {},
        onReleased: (_) {},
        notificationEventId: r'$ring',
        callerMembershipEventId: r'$caller-membership',
        mediaOverride: _FakeMedia(),
        captureOverride: CallCaptureService(sink: _NullSink()),
      );
      await pumpEventQueue();
      session.timelineEventsOverride = () async => const [];
      session.endCall();
      await pumpEventQueue();

      await session.survivorCheckNowForTest();

      // A survivor writing a missed or declined outcome would be fabricating
      // one it cannot know; only the caller decides those.
      expect(room.cards, isEmpty);
    });
  });

  // The ongoing-call notification is drawn by Android, which has none of the
  // app's translations. Its mute button and its channel name therefore have
  // to be handed over, and a call that forgets shows a learner reading their
  // phone in Hindi an English button on every call.
  test('the platform is given the labels in the learner\'s language', () async {
    final client = await _bareClient();
    final seen = <({String mute, String channel})>[];
    CallSession.start(
      room: _RecordingRoom(id: '!r:server', client: client),
      video: false,
      callService: _FakeCalls(client),
      transcribe: (request) async =>
          SpeechToTextResponseModel(results: const []),
      userL1: 'en',
      userL2: 'es',
      analytics: (eventId, uses, language) async {},
      onReleased: (_) {},
      platformLabels: (mute: 'Mute-hi', channel: 'Channel-hi'),
      mediaOverride: _FakeMedia(),
      captureOverride: CallCaptureService(sink: _NullSink()),
      foregroundOverride: _LabelSpyForeground(seen),
    );
    await pumpEventQueue();

    expect(seen, isNotEmpty, reason: 'the service was never started');
    expect(seen.single.mute, 'Mute-hi');
    expect(seen.single.channel, 'Channel-hi');
  });

  group('the ended-call summary', () {
    Future<(CallSession, List<CallSession>)> answeredThenEnded() async {
      final client = await _bareClient();
      final released = <CallSession>[];
      final media = _FakeMedia();
      final session = CallSession.start(
        room: _RecordingRoom(id: '!r:server', client: client),
        video: false,
        callService: _FakeCalls(client),
        transcribe: (request) async =>
            SpeechToTextResponseModel(results: const []),
        userL1: 'en',
        userL2: 'es',
        analytics: (eventId, uses, language) async {},
        onReleased: released.add,
        mediaOverride: media,
        captureOverride: CallCaptureService(sink: _NullSink()),
      );
      await pumpEventQueue();
      final roster = media.fakeRoster!;
      roster.identities = {'@friend:fakeServer.notExisting:FRIENDDEV'};
      roster.recompute();
      await pumpEventQueue();
      session.endCall();
      await pumpEventQueue();
      return (session, released);
    }

    test(
      'an answered call holds a summary; the busy claim is already free',
      () async {
        final (session, released) = await answeredThenEnded();
        expect(session.showingSummary, isTrue);
        expect(
          session.isOver,
          isTrue,
          reason: 'a redial must be able to step over the held session',
        );
        expect(released, isEmpty, reason: 'the handover is what waits');
        expect(session.endedAt, isNotNull);
        session.dismissSummary();
        await pumpEventQueue();
        expect(released, hasLength(1));
      },
    );

    test('the summary dismisses itself after its lifetime', () async {
      final (session, released) = await answeredThenEnded();
      expect(session.showingSummary, isTrue);
      await Future<void>.delayed(
        CallSession.summaryLifetime + const Duration(milliseconds: 300),
      );
      await pumpEventQueue();
      expect(released, hasLength(1), reason: 'the 3s timer handed it over');
      expect(session.showingSummary, isFalse);
    });

    test('a call nobody answered releases at once, as before', () async {
      final client = await _bareClient();
      final released = <CallSession>[];
      final session = CallSession.start(
        room: _RecordingRoom(id: '!r:server', client: client),
        video: false,
        callService: _FakeCalls(client),
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
      session.endCall();
      await pumpEventQueue();
      expect(session.showingSummary, isFalse, reason: 'no conversation to sum');
      expect(released, hasLength(1));
    });

    test(
      'disposal before the timer fires neither crashes nor double-releases',
      () async {
        final (session, released) = await answeredThenEnded();
        expect(session.showingSummary, isTrue);
        session.dispose();
        await Future<void>.delayed(
          CallSession.summaryLifetime + const Duration(milliseconds: 300),
        );
        await pumpEventQueue();
        expect(released.length, lessThanOrEqualTo(1));
      },
    );
  });

  group('a finished call always leaves a card', () {
    // The record's own tests cover HOW a card is written. Nothing checked
    // that the SESSION writes one, and a browser run found a call both sides
    // agreed had happened, answered and hung up, with no card on either side.
    test('an answered call that is hung up writes exactly one', () async {
      final client = await _bareClient();
      final calls = _FakeCalls(client);
      final media = _FakeMedia();
      final spy = _SpyRecord();
      final session = CallSession.start(
        room: matrix.Room(id: '!card:server', client: client),
        video: false,
        callService: calls,
        transcribe: (request) async =>
            SpeechToTextResponseModel(results: const []),
        userL1: 'en',
        userL2: 'es',
        analytics: (eventId, uses, language) async {},
        onReleased: (_) {},
        mediaOverride: media,
        captureOverride: CallCaptureService(sink: _NullSink()),
        recordOverride: spy,
      );
      await pumpEventQueue();
      final roster = media.fakeRoster!;
      roster.identities = {'@friend:fakeServer.notExisting:FRIENDDEV'};
      roster.recompute();
      await pumpEventQueue();

      session.endCall();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await pumpEventQueue();

      expect(spy.cards.length, 1, reason: 'one call, one card');
      expect(spy.cards.single.answered, isTrue);
      expect(spy.cards.single.declined, isFalse);
    });
  });

  group('a ring that never went out', () {
    // pangeachat/.github#410: the membership echo can time out and, unlike
    // the ordinary case, the late-anchor retry ActiveCall runs afterwards can
    // ALSO come back empty -- the ring is truly never sent, no push ever
    // goes out, the callee's phone never rings. But reaching the SFU on our
    // own end does not depend on that echo, so the call still climbs to
    // CallStage.connected regardless. Treating "we reached the SFU" as proof
    // the call mattered wrote "No answer" for a call the other person was
    // never told about -- an answer nobody was ever asked to give.
    test('leaves no card; nobody was ever told about it', () async {
      final client = await _bareClient();
      final calls = _NeverEchoesCalls(client);
      final media = _FakeMedia();
      final spy = _SpyRecord();
      final session = CallSession.start(
        room: matrix.Room(id: '!phantom:server', client: client),
        video: false,
        callService: calls,
        transcribe: (request) async =>
            SpeechToTextResponseModel(results: const []),
        userL1: 'en',
        userL2: 'es',
        analytics: (eventId, uses, language) async {},
        onReleased: (_) {},
        mediaOverride: media,
        captureOverride: CallCaptureService(sink: _NullSink()),
        recordOverride: spy,
      );
      await pumpEventQueue();

      // Nobody ever joined -- there was nobody left to answer, because
      // nobody was ever told this call existed.
      session.endCall();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await pumpEventQueue();

      expect(
        spy.cards,
        isEmpty,
        reason:
            'the ring never reached the other side; recording "no answer" '
            'would state an answer that was never asked for',
      );
    });
  });

  group('a call nobody can hear', () {
    // The one failure on this screen a learner cannot discover for
    // themselves: the call is up, the timer runs, and the other person hears
    // silence. It must be said out loud.
    test('says so, rather than looking like an ordinary call', () async {
      final client = await _bareClient();
      final calls = _FakeCalls(client);
      final media = _FakeMedia()..refuseCapture = true;
      final session = CallSession.start(
        room: matrix.Room(id: '!mute:server', client: client),
        video: false,
        callService: calls,
        transcribe: (request) async =>
            SpeechToTextResponseModel(results: const []),
        userL1: 'en',
        userL2: 'es',
        analytics: (eventId, uses, language) async {},
        onReleased: (_) {},
        mediaOverride: media,
        captureOverride: CallCaptureService(sink: _NullSink()),
      );
      await pumpEventQueue();
      expect(session.microphoneRefused, isTrue);
    });
  });

  group('a video call whose camera never opened', () {
    test('does not claim the camera is on', () async {
      final client = await _bareClient();
      final calls = _FakeCalls(client);
      final media = _FakeMedia()..refuseCamera = true;
      final session = CallSession.start(
        room: matrix.Room(id: '!cam:server', client: client),
        video: true,
        callService: calls,
        transcribe: (request) async =>
            SpeechToTextResponseModel(results: const []),
        userL1: 'en',
        userL2: 'es',
        analytics: (eventId, uses, language) async {},
        onReleased: (_) {},
        mediaOverride: media,
        captureOverride: CallCaptureService(sink: _NullSink()),
      );
      await pumpEventQueue();
      expect(
        session.cameraOn,
        isFalse,
        reason: 'the control must show the camera the call actually has',
      );
    });

    test('a camera that did open is still reported on', () async {
      final client = await _bareClient();
      final calls = _FakeCalls(client);
      final session = CallSession.start(
        room: matrix.Room(id: '!cam2:server', client: client),
        video: true,
        callService: calls,
        transcribe: (request) async =>
            SpeechToTextResponseModel(results: const []),
        userL1: 'en',
        userL2: 'es',
        analytics: (eventId, uses, language) async {},
        onReleased: (_) {},
        mediaOverride: _FakeMedia(),
        captureOverride: CallCaptureService(sink: _NullSink()),
      );
      await pumpEventQueue();
      expect(session.cameraOn, isTrue);
    });
  });

  group('the summary that follows a call', () {
    // Reported from the phone: the timer ran to 1:08, the call ended, and the
    // summary said 0:14. It was showing the segmented talk time, which after
    // a rejoin counts only the stretch since returning -- so the number the
    // learner had just been watching vanished.
    test(
      'shows the length of the CALL, not the stretch since a rejoin',
      () async {
        final client = await _bareClient();
        final calls = _FakeCalls(client);
        final media = _FakeMedia();
        final session = CallSession.start(
          room: matrix.Room(id: '!sum:server', client: client),
          video: false,
          callService: calls,
          transcribe: (request) async =>
              SpeechToTextResponseModel(results: const []),
          userL1: 'en',
          userL2: 'es',
          analytics: (eventId, uses, language) async {},
          onReleased: (_) {},
          rejoinAnchor: r'$original-membership',
          // Returned to a call that began a minute and eight seconds ago.
          rejoinSince: DateTime.now().subtract(const Duration(seconds: 68)),
          mediaOverride: media,
          captureOverride: CallCaptureService(sink: _NullSink()),
        );
        await pumpEventQueue();
        final roster = media.fakeRoster!;
        roster.identities = {'@friend:fakeServer.notExisting:FRIENDDEV'};
        roster.recompute();
        await pumpEventQueue();

        expect(
          session.callDuration.inSeconds,
          closeTo(68, 4),
          reason: 'the summary follows the clock the learner was watching',
        );
        expect(
          session.call.talkDuration.inSeconds,
          lessThan(20),
          reason: 'the talk time really is only the stretch since returning',
        );
      },
    );
  });

  group('the clock both people read', () {
    // The breadcrumb was written by THIS device's clock, and the timer
    // subtracts from that same clock. `origin_server_ts` is the SERVER's: a
    // device two minutes off it read two minutes into a thirty-second call
    // while the other side still read thirty seconds.
    test('the breadcrumb clock wins over the server clock', () async {
      final client = await _bareClient();
      final calls = _FakeCalls(client);
      // What the server would say -- wrong by two minutes on this device.
      calls.membershipWrittenAtValue = DateTime.now().subtract(
        const Duration(minutes: 2, seconds: 30),
      );
      final media = _FakeMedia();
      final session = CallSession.start(
        room: matrix.Room(id: '!clock:server', client: client),
        video: false,
        callService: calls,
        transcribe: (request) async =>
            SpeechToTextResponseModel(results: const []),
        userL1: 'en',
        userL2: 'es',
        analytics: (eventId, uses, language) async {},
        onReleased: (_) {},
        rejoinAnchor: r'$original-membership',
        rejoinSince: DateTime.now().subtract(const Duration(seconds: 30)),
        mediaOverride: media,
        captureOverride: CallCaptureService(sink: _NullSink()),
      );
      await pumpEventQueue();
      final roster = media.fakeRoster!;
      roster.identities = {'@friend:fakeServer.notExisting:FRIENDDEV'};
      roster.recompute();
      await pumpEventQueue();

      final shown = DateTime.now().difference(session.callStartedAt!);
      expect(
        shown.inSeconds,
        closeTo(30, 3),
        reason: 'the device that wrote the crumb reads its own clock',
      );
    });

    test(
      'a rejoined session continues the call, it does not restart it',
      () async {
        // A learner who refreshed watched 0:00 while the other side read 4:12 --
        // one call, two answers. The rejoin carries the call's own start.
        final client = await _bareClient();
        final calls = _FakeCalls(client);
        calls.membershipWrittenAtValue = DateTime.now().subtract(
          const Duration(minutes: 4, seconds: 12),
        );
        final media = _FakeMedia();
        final session = CallSession.start(
          room: matrix.Room(id: '!r:server', client: client),
          video: false,
          callService: calls,
          transcribe: (request) async =>
              SpeechToTextResponseModel(results: const []),
          userL1: 'en',
          userL2: 'es',
          analytics: (eventId, uses, language) async {},
          onReleased: (_) {},
          rejoinAnchor: r'$original-membership',
          mediaOverride: media,
          captureOverride: CallCaptureService(sink: _NullSink()),
        );
        await pumpEventQueue();
        final roster = media.fakeRoster!;
        roster.identities = {'@friend:fakeServer.notExisting:FRIENDDEV'};
        roster.recompute();
        await pumpEventQueue();

        final shown = DateTime.now().difference(session.callStartedAt!);
        expect(
          shown.inSeconds,
          greaterThan(240),
          reason: 'the clock reads where the call actually is',
        );
        // The CARD is a different quantity and must not inherit the gap.
        expect(
          session.talkDuration,
          lessThan(const Duration(seconds: 5)),
          reason: 'talk time is what anyone could hear, not wall clock',
        );
      },
    );
  });

  group('the call identity every writer shares', () {
    test('a plain call: the placer, keyed by its own membership', () {
      final id = CallSession.resolveCallIdentity(
        placed: true,
        peerAlsoPlaced: false,
        myUserId: '@me:s',
        peerUserId: '@peer:s',
        ownMembershipId: r'$mine',
        peerRingMembershipId: null,
        callerMembershipEventId: null,
      );
      expect(id.key, r'$mine');
      expect(id.caller, '@me:s');
    });

    test('the answerer: keyed by the ring, the caller named', () {
      final id = CallSession.resolveCallIdentity(
        placed: false,
        peerAlsoPlaced: false,
        myUserId: '@me:s',
        peerUserId: '@peer:s',
        ownMembershipId: r'$mine',
        peerRingMembershipId: null,
        callerMembershipEventId: r'$theirs',
      );
      expect(id.key, r'$theirs');
      expect(id.caller, '@peer:s');
    });

    test('glare: BOTH sides stamp the tie-break winner, not themselves', () {
      // '@a' beats '@b'. The winner keys by its own membership; the loser by
      // the membership the winner's simultaneous ring named. `placedCall ?
      // me : peer` here would have named the LOSER on the loser's card.
      final winner = CallSession.resolveCallIdentity(
        placed: true,
        peerAlsoPlaced: true,
        myUserId: '@a:s',
        peerUserId: '@b:s',
        ownMembershipId: r'$a-membership',
        peerRingMembershipId: r'$b-membership',
        callerMembershipEventId: null,
      );
      final loser = CallSession.resolveCallIdentity(
        placed: true,
        peerAlsoPlaced: true,
        myUserId: '@b:s',
        peerUserId: '@a:s',
        ownMembershipId: r'$b-membership',
        peerRingMembershipId: r'$a-membership',
        callerMembershipEventId: null,
      );
      expect(winner.key, r'$a-membership');
      expect(loser.key, r'$a-membership', reason: 'one call, one key');
      expect(winner.caller, '@a:s');
      expect(loser.caller, '@a:s', reason: 'the card names the winner');
    });

    test(
      'the sub-millisecond glare: both derived joiners still share a key',
      () {
        // Each side saw the other in the SFU before deciding, so neither
        // placed -- and neither fast-writes. The shared key is what lets the
        // survivor path write the card that used to go missing entirely.
        final a = CallSession.resolveCallIdentity(
          placed: false,
          peerAlsoPlaced: true,
          myUserId: '@a:s',
          peerUserId: '@b:s',
          ownMembershipId: r'$a-membership',
          peerRingMembershipId: r'$b-membership',
          callerMembershipEventId: null,
        );
        final b = CallSession.resolveCallIdentity(
          placed: false,
          peerAlsoPlaced: true,
          myUserId: '@b:s',
          peerUserId: '@a:s',
          ownMembershipId: r'$b-membership',
          peerRingMembershipId: r'$a-membership',
          callerMembershipEventId: null,
        );
        expect(a.key, r'$a-membership');
        expect(b.key, r'$a-membership', reason: 'one call, one key');
        expect(a.caller, '@a:s');
        expect(b.caller, '@a:s');
      },
    );
  });
}

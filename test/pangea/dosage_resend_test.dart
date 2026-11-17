import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics/listening_exposure_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_entry.dart';
import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';
import 'package:fluffychat/features/dosage/dosage_message_signals.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/wav_writer.dart';
import 'get_test_client.dart';

/// [DosageMessageSignals.emitForResend] is the real sendAgain() wiring for the
/// chat "resend" action: it resends the failed event, then emits the envelope
/// under the RESOLVED (post-resend) event id, counting only the learner's own
/// text — the reply fallback stripped — never the stale id or the quoted
/// message. The room id is FakeMatrixApi's magic `!1234:...`, whose `/send/` the
/// fake homeserver accepts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late List<http.Request> posts;
  late http.Client mock;

  const userId = '@test:fakeServer.notExisting';
  const roomId = '!1234:fakeServer.notExisting';

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('dosage_resend_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() async {
    // Dosage on, so the emit actually POSTs (not the ship-dark no-op).
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
      },
    );
    client = await getTestClient(httpClient: _BinaryUploads());
    ListeningExposureBuffer.debugResetAccounts();
    posts = [];
    mock = MockClient((req) async {
      posts.add(req);
      return http.Response('', 202);
    });
  });

  tearDown(() async {
    ListeningExposureBuffer.debugResetAccounts();
    await client.dispose();
  });

  Event failedEvent({required Map<String, dynamic> content}) => Event(
    type: EventTypes.Message,
    content: content,
    status: EventStatus.error,
    eventId: '\$failed:fakeServer.notExisting',
    senderId: userId,
    originServerTs: DateTime.utc(2026, 1, 1, 12),
    room: Room(id: roomId, client: client),
  );

  List<Map<String, dynamic>> envelopes() => posts
      .where((r) => r.url.path.contains('/dosage/message-events'))
      .expand(
        (r) =>
            (jsonDecode(r.body)['events'] as List).cast<Map<String, dynamic>>(),
      )
      .toList();

  test(
    'a resent reply emits under the RESOLVED id, counting only the reply text',
    () async {
      final event = failedEvent(
        content: {
          'msgtype': 'm.text',
          // A rich-reply body: quoted fallback + the learner's actual reply.
          'body': '> <@bob:fakeServer.notExisting> hallo\n\nhola reply',
          'm.relates_to': {
            'm.in_reply_to': {'event_id': '\$orig:fakeServer.notExisting'},
          },
        },
      );
      final tracker = DosageEngagementTracker(
        now: () => DateTime.utc(2026),
        httpClient: mock,
      );

      await DosageMessageSignals.emitForResend(
        event,
        client: mock,
        tracker: tracker,
      );
      await pumpEventQueue(); // let the fire-and-forget envelope POST land

      expect(envelopes(), hasLength(1), reason: 'the resent reply emitted');
      final envelope = envelopes().single;
      // The RESOLVED, post-resend event id — never the failed one.
      expect(envelope['msg_id'], isNotEmpty);
      expect(
        envelope['msg_id'],
        isNot('\$failed:fakeServer.notExisting'),
        reason:
            'the envelope must carry the resend-resolved id, not the stale one',
      );
      // Only the learner's own reply text is counted — NOT the quoted fallback.
      expect(envelope['char_count'], 'hola reply'.length);
    },
  );

  test('a resent file carries no learner text — nothing emitted', () async {
    final event = failedEvent(
      content: {'msgtype': 'm.image', 'body': 'photo.jpg', 'url': 'mxc://x/y'},
    );
    final tracker = DosageEngagementTracker(
      now: () => DateTime.utc(2026),
      httpClient: mock,
    );

    await DosageMessageSignals.emitForResend(
      event,
      client: mock,
      tracker: tracker,
    );
    await pumpEventQueue();

    expect(envelopes(), isEmpty, reason: 'a file resend is not a learner turn');
  });

  test('a forwarded text emits the envelope under the resolved id', () async {
    final room = Room(id: roomId, client: client);
    final tracker = DosageEngagementTracker(
      now: () => DateTime.utc(2026),
      httpClient: mock,
    );

    await DosageMessageSignals.emitForForwardedContent(
      room,
      {'msgtype': 'm.text', 'body': 'shared learner text'},
      client: mock,
      tracker: tracker,
    );
    await pumpEventQueue();

    expect(envelopes(), hasLength(1), reason: 'forwarded text is a send');
    final envelope = envelopes().single;
    expect(envelope['room_id'], roomId);
    expect(envelope['msg_id'], isNotEmpty);
    expect(envelope['char_count'], 'shared learner text'.length);
  });

  test('a forwarded image carries no learner text — nothing emitted', () async {
    final room = Room(id: roomId, client: client);
    final tracker = DosageEngagementTracker(
      now: () => DateTime.utc(2026),
      httpClient: mock,
    );

    await DosageMessageSignals.emitForForwardedContent(
      room,
      {'msgtype': 'm.image', 'body': 'photo.jpg', 'url': 'mxc://x/y'},
      client: mock,
      tracker: tracker,
    );
    await pumpEventQueue();

    expect(
      envelopes(),
      isEmpty,
      reason: 'a forwarded image is not learner text',
    );
  });

  group('a resent voice message counts toward speaking (#9857)', () {
    const failedId = '\$failed:fakeServer.notExisting';

    // The voice_send rows held for the account, drained once.
    List<OneConstructUse> voiceRows() =>
        (ListeningExposureBuffer.forAccount(userId)?.drainAudioEntries() ??
                const <OneConstructUse>[])
            .where((r) => r.category == DosageAudioEntry.voiceCategory)
            .toList();

    // A failed m.audio whose file is still cached for the retry, exactly as
    // Room.sendFileEvent leaves it after a send that never landed.
    Event failedVoice({int? infoDuration, Uint8List? bytes}) {
      final event = failedEvent(
        content: {
          'msgtype': 'm.audio',
          'body': 'voice.wav',
          'info': {'mimetype': 'audio/wav', 'duration': ?infoDuration},
        },
      );
      event.room.sendingFilePlaceholders[failedId] = MatrixAudioFile(
        bytes: bytes ?? pcm16ToWav(Uint8List(32000)),
        name: 'voice.wav',
      );
      return event;
    }

    test(
      'records exactly one row, under the NEW id, with info.duration',
      () async {
        await DosageMessageSignals.emitForResend(
          failedVoice(infoDuration: 21100),
          client: mock,
        );

        final rows = voiceRows();
        expect(rows, hasLength(1), reason: 'one resend, one voice_send row');
        expect(rows.single.id, isNotEmpty);
        expect(
          rows.single.id,
          isNot(failedId),
          reason: 'keyed by the resolved m.audio id, never the failed one',
        );
        expect(rows.single.durMs, 21100);
      },
    );

    test('with no info.duration, the length is read from the WAV', () async {
      // 1.5 s of 16 kHz mono PCM16.
      await DosageMessageSignals.emitForResend(
        failedVoice(bytes: pcm16ToWav(Uint8List(48000))),
        client: mock,
      );

      expect(voiceRows().single.durMs, 1500);
    });

    test('a resend that cannot send records nothing', () async {
      // The file is no longer cached, so sendAgain throws: nothing landed.
      final event = failedVoice(infoDuration: 21100);
      event.room.sendingFilePlaceholders.clear();

      await DosageMessageSignals.emitForResend(event, client: mock);

      expect(voiceRows(), isEmpty);
    });

    test('a voice message that already sent is not counted again', () async {
      // A first-time send records its own row in chat.dart; the resend path
      // must add nothing for an event that is not in the error state.
      final event = Event(
        type: EventTypes.Message,
        content: {
          'msgtype': 'm.audio',
          'body': 'voice.wav',
          'info': {'duration': 21100},
        },
        status: EventStatus.synced,
        eventId: '\$sent:fakeServer.notExisting',
        senderId: userId,
        originServerTs: DateTime.utc(2026, 1, 1, 12),
        room: Room(id: roomId, client: client),
      );

      await DosageMessageSignals.emitForResend(event, client: mock);

      expect(voiceRows(), isEmpty);
    });
  });
}

/// [FakeMatrixApi] reads every request body as UTF-8, which a WAV upload is not,
/// so a voice resend could never upload against it. Answer the upload here and
/// hand everything else to the fake homeserver.
class _BinaryUploads extends http.BaseClient {
  final FakeMatrixApi _api = FakeMatrixApi();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path.endsWith('/media/v3/upload')) {
      return Future.value(
        http.StreamedResponse(
          Stream.value(utf8.encode('{"content_uri":"mxc://fake/voice"}')),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
    }
    return _api.send(request);
  }
}

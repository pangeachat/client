import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';
import 'package:fluffychat/features/dosage/dosage_message_signals.dart';
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
    client = await getTestClient();
    posts = [];
    mock = MockClient((req) async {
      posts.add(req);
      return http.Response('', 202);
    });
  });

  tearDown(() async {
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
}

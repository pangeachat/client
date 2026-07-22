import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'get_test_client.dart';

/// A notification quick-reply must emit the dosage message envelope. This drives
/// the REAL [notificationTap] entry point (not the emitter directly): it sends
/// the reply via the room, then emits under the resolved event id. The room id
/// is FakeMatrixApi's magic `!1234:...`, whose `/send/` the fake accepts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late List<http.Request> posts;

  const roomId = '!1234:fakeServer.notExisting';

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('notif_reply_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (m) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() async {
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
      },
    );
    posts = [];
    // The reply path emits WITHOUT injecting a client, so the POST goes through
    // the per-request factory — capture it there.
    DosageSignalsRepo.clientFactory = () => MockClient((req) async {
      posts.add(req);
      return http.Response('', 202);
    });
    client = await getTestClient();
    // Make the reply room known to the client so getRoomById resolves it.
    await client.handleSync(
      SyncUpdate.fromJson({
        'next_batch': 't1',
        'rooms': {
          'join': {
            roomId: {
              'state': {
                'events': [
                  {
                    'type': 'm.room.member',
                    'state_key': client.userID,
                    'content': {'membership': 'join'},
                    'sender': client.userID,
                    'event_id': '\$m1',
                    'origin_server_ts': 0,
                  },
                ],
              },
              'timeline': {'events': <dynamic>[], 'prev_batch': 'p'},
            },
          },
        },
      }),
    );
  });

  tearDown(() async {
    DosageSignalsRepo.clientFactory = http.Client.new;
    await client.dispose();
  });

  NotificationResponse replyResponse(String input) => NotificationResponse(
    notificationResponseType:
        NotificationResponseType.selectedNotificationAction,
    actionId: FluffyChatNotificationActions.reply.name,
    input: input,
    // FluffyChatPushPayload.fromString splits on '|': clientName|roomId|eventId
    payload: '${client.clientName}|$roomId|\$evt:fakeServer.notExisting',
    data: const {},
  );

  test(
    'a notification reply emits the dosage envelope for the reply',
    () async {
      expect(
        client.getRoomById(roomId),
        isNotNull,
        reason: 'precondition: the reply room is known to the client',
      );

      await notificationTap(replyResponse('hola mundo'), client: client);
      await pumpEventQueue();

      final envelopes = posts
          .where((r) => r.url.path.contains('/dosage/message-events'))
          .expand(
            (r) => (jsonDecode(r.body)['events'] as List)
                .cast<Map<String, dynamic>>(),
          )
          .toList();
      expect(
        envelopes,
        hasLength(1),
        reason: 'the reply turn must emit exactly one envelope',
      );
      expect(envelopes.single['room_id'], roomId);
      expect(envelopes.single['char_count'], 'hola mundo'.length);
      // The resolved (server-assigned) event id, not a placeholder.
      expect((envelopes.single['msg_id'] as String), isNotEmpty);
    },
  );
}

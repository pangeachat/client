import 'dart:async';
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

import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';
import 'package:fluffychat/features/dosage/dosage_message_signals.dart';
import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';
import 'package:fluffychat/pangea/common/config/env_loader.dart';
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
    // COLD isolate: do NOT pre-load the env. The reply path must load it itself
    // (via ensureDosageEnvLoaded) or the emit no-ops — modelling the background
    // notification isolate. The loader is injected to load the flags.
    DosageMessageSignals.envLoader = () async => dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
      },
    );
    addTearDown(() => DosageMessageSignals.envLoader = EnvLoader.load);
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
    DosageEngagementTracker.debugResetAccounts();
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
      expect(
        dotenv.isInitialized,
        isFalse,
        reason:
            'precondition: cold isolate — the reply path must load the env '
            'itself for the emit to fire',
      );

      await notificationTap(
        replyResponse('hola mundo'),
        client: client,
        background: true,
      );
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

  test('a BACKGROUND reply AWAITS the envelope POST before returning', () async {
    // The background notification isolate disposes its client the instant
    // notificationTap returns, so a fire-and-forget emit would be dropped
    // before the POST lands. Gate the POST open and prove the background
    // reply does NOT return while it is still in flight.
    final gate = Completer<void>();
    var postSeen = false;
    DosageSignalsRepo.clientFactory = () => MockClient((req) async {
      if (req.url.path.contains('/dosage/message-events')) {
        postSeen = true;
        posts.add(req);
        await gate.future; // hold the response open
      }
      return http.Response('', 202);
    });

    final tap = notificationTap(
      replyResponse('hola mundo'),
      client: client,
      background: true,
    );
    var tapDone = false;
    unawaited(tap.then((_) => tapDone = true));

    // Let the send + the emit's POST get issued, but keep the POST open.
    await pumpEventQueue();
    expect(
      postSeen,
      isTrue,
      reason: 'the reply must have issued the envelope POST',
    );
    expect(
      tapDone,
      isFalse,
      reason:
          'a background reply must AWAIT the POST — it must not return while '
          'the POST is still in flight (the bg isolate would tear down first)',
    );

    gate.complete();
    await tap;
    expect(
      tapDone,
      isTrue,
      reason: 'once the POST completes, notificationTap returns',
    );
  });

  test(
    'a MAIN-isolate reply fire-and-forgets the emit (never blocks on the POST)',
    () async {
      // In the main isolate the client stays alive, so the reply must NOT wait
      // on the telemetry POST. Gate the POST open and prove notificationTap
      // still returns; the envelope lands afterward off the fire-and-forget emit.
      final gate = Completer<void>();
      var postSeen = false;
      DosageSignalsRepo.clientFactory = () => MockClient((req) async {
        if (req.url.path.contains('/dosage/message-events')) {
          postSeen = true;
          posts.add(req);
          await gate.future;
        }
        return http.Response('', 202);
      });

      // background defaults to false → main-isolate path.
      await notificationTap(replyResponse('hola mundo'), client: client);
      // Returned WITHOUT the POST having to complete (it is still gated).
      await pumpEventQueue();
      expect(
        postSeen,
        isTrue,
        reason: 'the main-isolate reply still issues the envelope POST',
      );

      gate.complete();
      await pumpEventQueue();
      final envelopes = posts
          .where((r) => r.url.path.contains('/dosage/message-events'))
          .toList();
      expect(
        envelopes,
        hasLength(1),
        reason: 'the fire-and-forget envelope lands once the POST is released',
      );
    },
  );
}

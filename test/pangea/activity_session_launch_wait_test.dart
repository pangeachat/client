// #9297 — Synapse delivers a new room in two syncs: the create event and the
// creator's join first, the rest of the initial state (activity reference,
// roles) in the next. launchActivitySession must not return between the two,
// or the start page opens without the launcher's role.

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/join_codes/join_code_constants.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/launch_activity_session.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'get_test_client.dart';
import 'sentry_capture_harness.dart';

/// Syncs a `pangea.activity_plan` state event into [roomId], the state
/// launchActivitySession waits for.
Future<void> seedActivityPlanState(Client client, String roomId) =>
    client.handleSync(
      SyncUpdate(
        nextBatch: 'seed-$roomId',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(
              state: [
                MatrixEvent(
                  type: PangeaEventTypes.activityPlan,
                  content: {'activity_id': 'act-1'},
                  stateKey: '',
                  senderId: client.userID!,
                  eventId: '\$plan-$roomId',
                  originServerTs: DateTime.now(),
                ),
              ],
            ),
          },
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  ActivityPlanModel plan() => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: 'jobs',
      mode: 'Roleplay',
      objective: 'introduce yourself',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'de',
      numberOfParticipants: 2,
    ),
    title: 'Speed-Dating Interview',
    description: 'Meet someone new.',
    learningObjective: 'lo',
    instructions: 'i',
    vocab: const [],
    activityId: 'act-1',
    roles: const {},
  );

  setUp(() async {
    // The bot invite reads Environment.botName → dotenv + GetStorage.
    final tempDir = await Directory.systemTemp.createTemp('launch_wait_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
    client = await getTestClient(
      importantStateEvents: {PangeaEventTypes.activityPlan},
    );
    FakeMatrixApi.calledEndpoints.clear();
  });

  tearDown(() async {
    await client.dispose();
  });

  test('returns only once the room\'s activity reference has synced', () async {
    const roomId = '!1234:fakeServer.notExisting';
    var returned = false;
    final launch = client
        .launchActivitySession(plan(), null)
        .then((id) => returned = true);

    // Let /createRoom and everything up to the wait run.
    for (
      var i = 0;
      i < 50 && FakeMatrixApi.calledEndpoints['/client/v3/createRoom'] == null;
      i++
    ) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    await Future.delayed(const Duration(milliseconds: 200));
    expect(
      FakeMatrixApi.calledEndpoints['/client/v3/createRoom'],
      isNotNull,
      reason: 'createRoom was never called',
    );
    expect(
      returned,
      isFalse,
      reason: 'launch returned before the room\'s initial state synced',
    );

    await seedActivityPlanState(client, roomId);
    await launch.timeout(const Duration(seconds: 2));
    expect(returned, isTrue);
  });

  // #9357 — the loading dialog shows each stage, so they must arrive in order
  // and the last one must arrive before the sync wait, not after it.
  test('reports every stage in order before waiting for sync', () async {
    const roomId = '!1234:fakeServer.notExisting';
    final stages = <ActivityLaunchStage>[];
    final launch = client.launchActivitySession(
      plan(),
      null,
      onStage: stages.add,
    );

    for (var i = 0; i < 50 && stages.length < 3; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    expect(stages, ActivityLaunchStage.values);

    await seedActivityPlanState(client, roomId);
    await launch.timeout(const Duration(seconds: 2));
  });

  // CLIENT-F37 — the bot invite runs behind the chat too, so the play-with-bot
  // dialog can invite the bot first. Synapse then refuses this one because the
  // bot has joined, which is what the invite was for: not a failure to report.
  // Any other refusal still is.
  group('the background bot invite', () {
    const roomId = '!1234:fakeServer.notExisting';
    const invite = '/client/v3/rooms/!1234%3AfakeServer.notExisting/invite';
    late SentryCaptureHarness sentry;

    setUp(() async {
      sentry = SentryCaptureHarness();
      await sentry.init();
    });

    tearDown(() => sentry.close());

    /// Starts a launch whose bot invite the homeserver refuses with [error],
    /// and returns the rest of it: from the room's state syncing to the
    /// refusal being handled.
    Future<Future<void> Function()> launchWithInviteRefused(
      String error,
    ) async {
      FakeMatrixApi.currentApi!.api['POST']![invite] = (_) => {
        'errcode': 'M_FORBIDDEN',
        'error': error,
      };
      final launch = client.launchActivitySession(plan(), null);
      // Let the steps before /createRoom report whatever they report in a
      // test client before the window under test opens.
      for (
        var i = 0;
        i < 50 &&
            FakeMatrixApi.calledEndpoints['/client/v3/createRoom'] == null;
        i++
      ) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      await Future.delayed(const Duration(milliseconds: 200));

      return () async {
        await seedActivityPlanState(client, roomId);
        await launch.timeout(const Duration(seconds: 2));
        await FakeMatrixApi.firstWhereValue(
          invite,
        ).timeout(const Duration(seconds: 2));
        // The response, and the catch that handles it, come after the request
        // is recorded.
        await Future.delayed(const Duration(milliseconds: 200));
      };
    }

    test('a refusal because the bot already joined is not reported', () async {
      final rest = await launchWithInviteRefused(
        'pangeabot is already in the room.',
      );
      await sentry.expectNoReport(rest);
    });

    test('any other refusal is still reported', () async {
      final rest = await launchWithInviteRefused(
        "You don't have permission to invite users",
      );
      final reported = sentry.capture(() {});
      await rest();
      final event = await reported;
      expect(event.level, SentryLevel.warning);
      expect(event.throwable, isA<MatrixException>());
    });
  });

  test('join rules use a join code requested ahead of time', () async {
    final event = await client.generateCustomJoinRules(
      JoinRules.knock,
      joinCode: Future.value('early-code'),
    );
    expect(event.content[JoinCodeConstants.accessCode], 'early-code');
  });
}

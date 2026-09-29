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

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/routes/chat/activity_sessions/launch_activity_session.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'get_test_client.dart';

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
}

// A session room's history must be readable from BEFORE a member joined.
//
// An activity session is a shared, course-scoped conversation: a teacher who
// joins to review it, or a coursemate who knocks in partway through, has to be
// able to read what was already said. Matrix leaves `m.room.history_visibility`
// to the server default when the client does not set it, and the restrictive
// defaults (`joined` / `invited`) make earlier messages permanently unreadable
// to a later joiner — history visibility is evaluated per-event at send time and
// is NOT retroactive, so a room that starts restrictive can never be fixed.
//
// So the pin has to be an INITIAL state event, set atomically at creation, not a
// state write afterwards. These tests assert exactly that: the createRoom call
// carries `m.room.history_visibility: shared` in `initial_state`.
//
// `shared`, not `world_readable`: history opens to room MEMBERS only. The room
// is still created private with a knock / knock-restricted join rule, so
// membership remains the gate.

import 'dart:convert';
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
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'get_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  ActivityPlanRequest req() => ActivityPlanRequest(
    topic: 'jobs',
    mode: 'Roleplay',
    objective: 'introduce yourself',
    media: MediaEnum.nan,
    cefrLevel: LanguageLevelTypeEnum.a1,
    languageOfInstructions: 'en',
    targetLanguage: 'de',
    numberOfParticipants: 2,
  );

  ActivityPlanModel plan() => ActivityPlanModel(
    req: req(),
    title: 'Speed-Dating Interview',
    description: 'Meet someone new.',
    learningObjective: 'lo',
    instructions: 'i',
    vocab: const [],
    activityId: 'act-1',
    roles: const {},
  );

  /// The decoded body of the most recent createRoom request.
  ///
  /// FakeMatrixApi records the request body as the raw JSON string it received,
  /// so this asserts against the bytes that would actually go to the homeserver
  /// rather than against an in-memory object the SDK might reshape later.
  Map<String, dynamic> createRoomBody() {
    final calls = FakeMatrixApi.calledEndpoints['/client/v3/createRoom'];
    expect(calls, isNotNull, reason: 'createRoom was never called');
    expect(calls, isNotEmpty, reason: 'createRoom was never called');
    final recorded = calls!.last;
    return Map<String, dynamic>.from(
      recorded is String ? jsonDecode(recorded) as Map : recorded as Map,
    );
  }

  /// The `initial_state` array of the most recent createRoom request.
  List<Map<String, dynamic>> initialState() => List<Map<String, dynamic>>.from(
    (createRoomBody()['initial_state'] as List).map(
      (e) => Map<String, dynamic>.from(e as Map),
    ),
  );

  setUp(() async {
    // launchActivitySession invites the bot after createRoom, which reaches
    // Environment.botName → dotenv + GetStorage. Both are stubbed per-test
    // because flutter_test clears mock method-call handlers between tests, so a
    // setUpAll-only stub would be gone by the time the first test runs and the
    // call would throw before any assertion.
    final tempDir = await Directory.systemTemp.createTemp('hist_vis_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
    client = await getTestClient();
    FakeMatrixApi.calledEndpoints.clear();
  });

  tearDown(() async {
    await client.dispose();
  });

  group('session-room history visibility', () {
    test('is pinned to shared as an initial state event at creation', () async {
      await client.launchActivitySession(plan(), null);

      final events = initialState();
      final pinned = events.where(
        (e) => e['type'] == EventTypes.HistoryVisibility,
      );

      expect(
        pinned,
        hasLength(1),
        reason:
            'exactly one m.room.history_visibility must be sent at creation; '
            'zero leaves the server default in place and makes pre-join '
            'history permanently unreadable',
      );
      expect(
        pinned.single['content']['history_visibility'],
        HistoryVisibility.shared.text,
      );
      expect(
        pinned.single['content']['history_visibility'],
        isNot(HistoryVisibility.worldReadable.text),
        reason: 'history opens to members, never to non-members',
      );
    });

    test('does not disturb the join rules already set at creation', () async {
      await client.launchActivitySession(plan(), null);

      final types = initialState().map((e) => e['type']).toList();
      expect(types, contains(EventTypes.RoomJoinRules));
      expect(types, contains(EventTypes.HistoryVisibility));
    });

    test('the room is still created private', () async {
      await client.launchActivitySession(plan(), null);

      expect(
        createRoomBody()['visibility'],
        'private',
        reason:
            'shared history is only safe because membership is still the gate',
      );
    });
  });
}

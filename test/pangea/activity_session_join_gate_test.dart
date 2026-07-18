import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// The single gate that decides whether a discovered session is "joinable".
///
/// Both surfaces read the *same* predicate so a pin the map shows joinable is
/// one the start page will actually offer a Join for (never a green pin that
/// dead-ends at "Start"): the world map's coursemate discovery skips
/// `isStarted` sessions, and the start page's open-session list keeps only
/// `isActivityOpenToJoin` (= `!isStarted`, given members + an activity id). See
/// world-map.instructions.md ("Discovering joinable sessions").
///
/// Thin v3 refs resolve their plan through hydration (#7645), injected here
/// via [RoomSummaryResponse.referencePlanResolver]; only while hydration is
/// pending are seats unknown and the gate permissive.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bot = '@bot:test.pangea.chat';
  const ana = '@ana:pangea.chat';

  setUpAll(() async {
    // isFinished → BotName.byEnvironment → Environment.botName touches the
    // GetStorage('env_override') box, which needs path_provider. Stub the
    // channel to a temp dir so the box initializes silently (its read returns
    // null and botName falls back to dotenv) — same pattern as
    // analytics_events_repo_test.dart.
    final tempDir = await Directory.systemTemp.createTemp('join_gate_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
    // isFinished filters bot roles by BotName.byEnvironment (dotenv-backed).
    dotenv.testLoad(mergeWith: {'BOT_NAME': bot});
    // Hydration pending unless a test injects a resolved plan.
    RoomSummaryResponse.referencePlanResolver = (_) => null;
  });

  tearDown(() {
    RoomSummaryResponse.referencePlanResolver =
        RoomSummaryResponse.defaultReferencePlanResolver;
  });

  ActivityPlanModel plan(int roleCount) => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: 'jobs',
      mode: 'Roleplay',
      objective: 'introduce yourself',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'de',
      numberOfParticipants: roleCount,
    ),
    title: 'Retratos en El Morro',
    learningObjective: 'lo',
    instructions: 'i',
    vocab: const [],
    activityId: 'act-1',
    roles: {
      for (var i = 0; i < roleCount; i++)
        'role_$i': ActivityRole(
          id: 'role_$i',
          name: 'Role $i',
          goal: null,
          goals: const [],
        ),
    },
  );

  ActivityRolesModel fullRoles() => ActivityRolesModel({
    'role_0': ActivityRoleModel(id: 'role_0', userId: ana),
    'role_1': ActivityRoleModel(id: 'role_1', userId: bot),
  });

  group('RoomSummaryResponse — the joinable / open-to-join gate', () {
    test('a full session (every role held by a joined member, bot included) '
        'is started and NOT open to join — the #7645 case', () {
      final summary = RoomSummaryResponse(
        membershipSummary: {ana: 'join', bot: 'join'},
        activityId: 'act-1',
        activityPlan: plan(2),
        activityRoles: fullRoles(),
      );

      expect(summary.isStarted, isTrue);
      expect(summary.isActivityOpenToJoin, isFalse);
    });

    test('a full thin-ref session closes once its referenced plan hydrates — '
        'the v3 shape of the #7645 repro', () {
      RoomSummaryResponse.referencePlanResolver = (id) =>
          id == 'act-1' ? plan(2) : null;

      final summary = RoomSummaryResponse(
        membershipSummary: {ana: 'join', bot: 'join'},
        activityId: 'act-1',
        activityPlan: null,
        activityRoles: fullRoles(),
      );

      expect(summary.isStarted, isTrue);
      expect(summary.isActivityOpenToJoin, isFalse);
    });

    test('a session with a genuinely free seat stays open to join', () {
      final summary = RoomSummaryResponse(
        membershipSummary: {ana: 'join'},
        activityId: 'act-1',
        activityPlan: plan(2),
        activityRoles: ActivityRolesModel({
          'role_0': ActivityRoleModel(id: 'role_0', userId: ana),
        }),
      );

      expect(summary.isStarted, isFalse);
      expect(summary.isActivityOpenToJoin, isTrue);
    });

    test('a thin-ref session whose plan has not hydrated stays open: seats '
        'unknown → permissive, so the seat check never hides a possibly-'
        'joinable v3 session before its plan lands', () {
      final summary = RoomSummaryResponse(
        membershipSummary: {ana: 'join'},
        activityId: 'act-1',
        activityPlan: null,
        activityRoles: null,
      );

      expect(summary.isStarted, isFalse);
      expect(summary.isActivityOpenToJoin, isTrue);
    });

    test(
      'a session with no members is not open to join (joining would error)',
      () {
        final summary = RoomSummaryResponse(
          membershipSummary: {},
          activityId: 'act-1',
        );

        expect(summary.isActivityOpenToJoin, isFalse);
      },
    );

    test('a room without an activity id is not an open activity session', () {
      final summary = RoomSummaryResponse(
        membershipSummary: {ana: 'join'},
        activityId: null,
      );

      expect(summary.isActivityOpenToJoin, isFalse);
    });
  });
}

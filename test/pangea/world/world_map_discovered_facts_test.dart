import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/discovered_sessions_cache.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_pins_manager.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_signals.dart';
import '../get_test_client.dart';

/// #8895: the world map's discovered joinable facts are derived from the cached
/// previews at every signal recompute, not snapshotted by the discovery pass.
/// A thin v3 preview's seat count resolves through plan hydration, which lands
/// after the pass — so a fact frozen at discovery kept a full session's pin
/// green while its card row and start page (both reading the gate live) showed
/// no seats and no Join. Same predicate, evaluated at the same time, everywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bot = '@bot:test.pangea.chat';
  const ana = '@ana:pangea.chat';
  const roomId = '!session:pangea.chat';
  const nowMs = 1000;

  setUpAll(() async {
    // The gate's presence check → BotName.byEnvironment → Environment.botName
    // touches the GetStorage('env_override') box, which needs path_provider —
    // the same stub as activity_session_join_gate_test.dart.
    final tempDir = await Directory.systemTemp.createTemp('discovered_facts');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
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
      topic: 'home',
      mode: 'Roleplay',
      objective: 'compare safe and dangerous',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'de',
      numberOfParticipants: roleCount,
    ),
    title: 'Sicher oder gefährlich zu Hause?',
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

  /// A thin-ref (v3) preview of a two-seat session with both seats taken — the
  /// shape of the green card in the issue's clip.
  Map<String, Map<String, RoomSummaryResponse>> fullThinRefSession() => {
    'act-1': {
      roomId: RoomSummaryResponse(
        membershipSummary: {ana: 'join', bot: 'join'},
        activityId: 'act-1',
        activityRoles: ActivityRolesModel({
          'role_0': ActivityRoleModel(id: 'role_0', userId: ana),
          'role_1': ActivityRoleModel(id: 'role_1', userId: bot),
        }),
      ),
    },
  };

  List<ActivitySessionFacts> facts(
    Map<String, Map<String, RoomSummaryResponse>> previews, {
    bool joined = false,
  }) => discoveredSessionFacts(previews, isJoined: (_) => joined, nowMs: nowMs);

  group('discoveredSessionFacts', () {
    test('a full thin-ref session reads joinable while its plan is still '
        'hydrating — seats unknown, so the gate is permissive', () {
      final result = facts(fullThinRefSession());

      expect(result, hasLength(1));
      expect(result.single.activityId, 'act-1');
      expect(result.single.joinable, isTrue);
      expect(result.single.holdsRole, isFalse);
      expect(result.single.lastEventMs, nowMs);
    });

    test('the SAME cached previews yield no joinable fact once the plan '
        'hydrates to full — the pin re-gates with the card row and the start '
        'page instead of staying green (#8895)', () {
      final previews = fullThinRefSession();
      expect(facts(previews), hasLength(1));

      RoomSummaryResponse.referencePlanResolver = (id) =>
          id == 'act-1' ? plan(2) : null;

      expect(facts(previews), isEmpty);
    });

    test('a hydrated session with a free seat keeps its joinable fact', () {
      RoomSummaryResponse.referencePlanResolver = (_) => plan(2);
      final previews = {
        'act-1': {
          roomId: RoomSummaryResponse(
            membershipSummary: {ana: 'join'},
            activityId: 'act-1',
            activityRoles: ActivityRolesModel({
              'role_0': ActivityRoleModel(id: 'role_0', userId: ana),
            }),
          ),
        },
      };

      expect(facts(previews), hasLength(1));
    });

    test('a room the learner has joined is left to its local facts', () {
      expect(facts(fullThinRefSession(), joined: true), isEmpty);
    });
  });

  group('WorldMapPinsManager.recomputeProgress — the production shell', () {
    late Client client;

    setUp(() async {
      client = await getTestClient();
    });

    tearDown(() async {
      DiscoveredSessionsCache.instance.clear();
      await client.dispose();
    });

    test('a discovered full session colours its pin joinable while hydrating, '
        'then drops it once the plan hydrates — with no discovery pass in '
        'between (#8895)', () {
      final manager = WorldMapPinsManager();
      DiscoveredSessionsCache.instance.replaceAll(fullThinRefSession());

      manager.recomputeProgress(client);
      expect(manager.signals['act-1']?.state, ActivityPinState.joinable);

      RoomSummaryResponse.referencePlanResolver = (_) => plan(2);
      manager.recomputeProgress(client);
      expect(manager.signals['act-1']?.state, isNot(ActivityPinState.joinable));
    });

    test(
      'a session room the learner has joined is left to its local facts',
      () {
        client.rooms.add(
          Room(id: roomId, client: client, membership: Membership.join),
        );
        final manager = WorldMapPinsManager();
        DiscoveredSessionsCache.instance.replaceAll(fullThinRefSession());

        manager.recomputeProgress(client);
        expect(
          manager.signals['act-1']?.state,
          isNot(ActivityPinState.joinable),
        );
      },
    );
  });
}

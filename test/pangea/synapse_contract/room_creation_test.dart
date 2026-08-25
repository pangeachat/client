@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/launch_activity_session.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/chat_list/course_default_chats_enum.dart';
import 'package:fluffychat/routes/chat_list/default_chats_room_extension.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../endpoint_test_env.dart';
import 'contract_harness.dart';

/// Tier 1 — room-creation contract tests (client#8565).
///
/// Each test drives the client's real creation extension against the live
/// Synapse at `SYNAPSE_URL`, then asserts the server-side state read-back:
/// the custom request shape must not only be accepted, it must survive the
/// server round-trip unchanged. This is the layer that broke in the last
/// Synapse upgrade attempt.
void main() {
  if (!EndpointTestEnv.available) {
    test(
      'synapse contract suite is local-only',
      () {},
      skip: 'requires client/.env',
    );
    return;
  }

  late Client client;

  setUpAll(() async {
    await ContractHarness.initTestEnvironment();
    client = await ContractHarness.loggedIn(ContractHarness.learnerA);
  });

  tearDownAll(() async {
    await ContractHarness.dispose(client);
  });

  Future<String> makeCourseSpace({String? nameSuffix}) =>
      client.createPangeaSpace(
        name:
            'Contract Course ${nameSuffix ?? ''} '
            '${DateTime.now().millisecondsSinceEpoch}',
        topic: 'synapse-contract-suite fixture',
        visibility: Visibility.public,
        joinRules: JoinRules.knock,
        spaceChild: 0,
        initialState: [
          StateEvent(
            type: 'pangea.course_plan',
            content: {'uuid': 'contract-course-uuid', 'l2': 'es'},
          ),
          StateEvent(
            type: 'pangea.course_settings',
            content: {'require_analytics_access': true},
          ),
        ],
      );

  group('createPangeaSpace (course space)', () {
    test('the launched-course shape round-trips through Synapse', () async {
      final roomId = await makeCourseSpace();
      expect(roomId, isNotEmpty);

      final state = await ContractHarness.serverState(client, roomId);

      // m.room.create carries the space type from creationContent.
      expect(state['m.room.create']?['']?['type'], 'm.space');

      // The custom join-rules content: knock, with the non-spec access_code
      // key intact. A server that starts validating join_rules content
      // strictly (or a module regression) breaks course join codes here.
      final joinRules = state['m.room.join_rules']?[''];
      expect(joinRules, isNotNull, reason: 'join_rules initial state missing');
      expect(joinRules?['join_rule'], 'knock');
      expect(
        joinRules?['access_code'],
        isA<String>().having((c) => c.isNotEmpty, 'non-empty', true),
        reason: 'non-spec access_code must survive the server round-trip',
      );

      // power_level_content_override is a SHALLOW merge server-side: the
      // override's top-level keys replace Synapse's generated content, and
      // the untouched generated users map must still hold the creator at 100.
      final powerLevels = state['m.room.power_levels']?[''];
      expect(powerLevels, isNotNull);
      expect((powerLevels?['users'] as Map?)?[client.userID], 100);
      final eventLevels = powerLevels?['events'] as Map?;
      expect(
        eventLevels?['m.space.child'],
        0,
        reason: 'spaceChild: 0 lets course members attach activity sessions',
      );
      expect(eventLevels?['m.room.power_levels'], 100);
      expect(eventLevels?['m.room.join_rules'], 100);
      expect(powerLevels?['state_default'], 50);

      // Custom initial-state events landed as sent.
      expect(state['pangea.course_plan']?[''], {
        'uuid': 'contract-course-uuid',
        'l2': 'es',
      });
      expect(state['pangea.course_settings']?[''], {
        'require_analytics_access': true,
      });

      // Topic round-trips (name is trimmed by the extension, not the server).
      expect(
        state['m.room.topic']?['']?['topic'],
        'synapse-contract-suite fixture',
      );
    });
  });

  group('launchActivitySession (activity session)', () {
    test('the session shape round-trips and attaches to the course', () async {
      final spaceId = await makeCourseSpace(nameSuffix: 'for-session');
      final space = client.getRoomById(spaceId);
      expect(space, isNotNull, reason: 'course space must be synced locally');

      final activity = ActivityPlanModel(
        req: ActivityPlanRequest(
          topic: 'contract suite',
          mode: 'discussion',
          objective: 'exercise the creation contract',
          media: MediaEnum.nan,
          cefrLevel: LanguageLevelTypeEnum.a1,
          languageOfInstructions: 'en',
          targetLanguage: 'es',
          numberOfParticipants: 2,
        ),
        title: 'Contract Activity',
        learningObjective: 'exercise the creation contract',
        instructions: 'talk',
        vocab: [],
        activityId: 'contract-activity-id',
        versionId: 'contract-version-1',
      );
      final role = ActivityRole(
        id: 'role-1',
        name: 'speaker',
        goal: null,
        goals: [],
      );

      final roomId = await client.launchActivitySession(
        activity,
        role,
        primarySpace: space,
      );
      final state = await ContractHarness.serverState(client, roomId);

      // The activity id rides inside the room type — the most custom
      // m.room.create content in the app.
      expect(
        state['m.room.create']?['']?['type'],
        '${PangeaRoomTypes.activitySession}:contract-activity-id',
      );

      // Thin CMS reference with the version pinned and the source course.
      expect(state[PangeaEventTypes.activityPlan]?[''], {
        'activity_id': 'contract-activity-id',
        'version_id': 'contract-version-1',
        'source_course_id': spaceId,
      });

      // The pre-claimed role landed in the single roles state event.
      final roles = state[PangeaEventTypes.activityRole]?[''];
      expect(
        roles,
        isNotNull,
        reason: 'pre-filled pangea.activity_roles missing',
      );

      // knock_restricted scoped to the course, access_code intact.
      final joinRules = state['m.room.join_rules']?[''];
      expect(joinRules?['join_rule'], 'knock_restricted');
      expect(
        (joinRules?['allow'] as List?)
            ?.map((a) => (a as Map)['room_id'])
            .toList(),
        contains(spaceId),
      );
      expect(joinRules?['access_code'], isA<String>());

      // History visibility pinned at creation.
      expect(
        state['m.room.history_visibility']?['']?['history_visibility'],
        'shared',
      );

      // PL override: creator re-listed at 100, bot seeded at 50, the three
      // pangea.* activity events writable at PL 0.
      final powerLevels = state['m.room.power_levels']?[''];
      final users = powerLevels?['users'] as Map?;
      expect(users?[client.userID], 100);
      expect(users?[BotName.byEnvironment], 50);
      final eventLevels = powerLevels?['events'] as Map?;
      expect(eventLevels?[PangeaEventTypes.activityPlan], 0);
      expect(eventLevels?[PangeaEventTypes.activityRole], 0);
      expect(eventLevels?[PangeaEventTypes.activitySummary], 0);

      // The session was shared into the course space (m.space.child written
      // by addSpaceChildKeepingParents), read from the SPACE's server state.
      final spaceState = await ContractHarness.serverState(client, spaceId);
      expect(
        spaceState['m.space.child']?[roomId],
        isNotNull,
        reason: 'session must be attached to the launching course',
      );

      // The bot invite is best-effort by design; assert it only when the bot
      // account exists on this homeserver.
      try {
        await client.getProfileFromUserId(BotName.byEnvironment);
        final botMember =
            state['m.room.member']?[BotName.byEnvironment]?['membership'];
        expect(botMember, 'invite', reason: 'bot should be invited at launch');
      } on MatrixException {
        // No bot account on this homeserver — the invite is expected to no-op.
      }
    });
  });

  group('createPangeaDirectChat (DM)', () {
    test('the unencrypted DM shape with bot_options round-trips', () async {
      // A fresh invitee each run: startDirectChat reuses an existing DM from
      // m.direct, and the point here is the creation shape.
      final invitee =
          'contract-dm-target-${DateTime.now().millisecondsSinceEpoch}';
      await ContractHarness.ensurePersona(invitee);
      final inviteeId = '@$invitee:${client.userID!.split(':').last}';

      final roomId = await client.createPangeaDirectChat(
        inviteeId,
        initialState: [
          StateEvent(
            type: PangeaEventTypes.botOptions,
            content: {
              'target_language': 'es',
              'language_level': 1,
              'mode': 'directChat',
            },
          ),
        ],
      );
      final state = await ContractHarness.serverState(client, roomId);

      // Encryption is forced OFF on every Pangea room — the choreographer and
      // bot must be able to read message content.
      expect(
        state['m.room.encryption'],
        isNull,
        reason: 'Pangea DMs must not be encrypted',
      );

      // The bot-options initial state landed as sent.
      expect(state[PangeaEventTypes.botOptions]?[''], {
        'target_language': 'es',
        'language_level': 1,
        'mode': 'directChat',
      });

      // It is a DM: the invitee holds an invite with is_direct.
      final inviteeMember = state['m.room.member']?[inviteeId];
      expect(inviteeMember?['membership'], 'invite');
      expect(inviteeMember?['is_direct'], true);
    });
  });

  group('createPangeaGroupChat (course group chat)', () {
    test('the knock_restricted group-chat shape round-trips', () async {
      final spaceId = await makeCourseSpace(nameSuffix: 'for-group-chat');

      final roomId = await client.createPangeaGroupChat(
        'Contract Group Chat',
        initialState: [
          await client.generateCustomJoinRules(
            JoinRules.knockRestricted,
            allowRoomId: spaceId,
          ),
        ],
        // The exact override space_details.dart passes: the production
        // constant, no users map.
        powerLevelContentOverride: RoomDefaults.defaultPowerLevelsContent(),
      );
      final state = await ContractHarness.serverState(client, roomId);

      expect(state['m.room.encryption'], isNull);

      final joinRules = state['m.room.join_rules']?[''];
      expect(joinRules?['join_rule'], 'knock_restricted');
      expect(
        (joinRules?['allow'] as List?)
            ?.map((a) => (a as Map)['room_id'])
            .toList(),
        [spaceId],
      );
      expect(joinRules?['access_code'], isA<String>());

      final powerLevels = state['m.room.power_levels']?[''];
      // No users override passed → Synapse's generated creator-100 survives.
      expect((powerLevels?['users'] as Map?)?[client.userID], 100);
      expect(powerLevels?['state_default'], 50);
      final eventLevels = powerLevels?['events'] as Map?;
      expect(eventLevels?[PangeaEventTypes.activityRole], 0);
    });
  });

  group('analytics room shape', () {
    // _makeAnalyticsRoom is private and MatrixState-coupled, so this mirrors
    // its createRoom call exactly (client_analytics_extension.dart), built
    // from the same production constants. If that method's shape changes,
    // update this mirror.
    test('the p.analytics creation shape round-trips', () async {
      const lang = 'es';
      final roomId = await client.createRoom(
        creationContent: {
          'type': PangeaRoomTypes.analytics,
          ModelKey.langCode: lang,
        },
        name: '${client.userID} $lang Analytics',
        topic: 'This room stores learning analytics for ${client.userID}.',
        preset: CreateRoomPreset.publicChat,
        visibility: Visibility.private,
        initialState: [
          StateEvent(
            type: EventTypes.RoomJoinRules,
            content: {ModelKey.joinRule: JoinRules.knock.name},
          ),
        ],
      );
      final state = await ContractHarness.serverState(client, roomId);

      // Non-spec keys in m.room.create must survive.
      final create = state['m.room.create']?[''];
      expect(create?['type'], PangeaRoomTypes.analytics);
      expect(create?[ModelKey.langCode], lang);

      // publicChat preset + private visibility: the join rule comes from the
      // initial join_rules event, and the room stays out of the directory.
      expect(state['m.room.join_rules']?['']?['join_rule'], 'knock');
      final visibility = await client.getRoomVisibilityOnDirectory(roomId);
      expect(visibility, Visibility.private);
    });
  });

  group('addDefaultChat (default course chats)', () {
    test('announcements: restricted PL keeps learners read-only', () async {
      final spaceId = await makeCourseSpace(nameSuffix: 'for-defaults');
      final space = client.getRoomById(spaceId);
      expect(space, isNotNull);

      final roomId = await space!.addDefaultChat(
        type: CourseDefaultChatsEnum.announcements,
        name: 'Announcements',
      );
      final state = await ContractHarness.serverState(client, roomId);

      // Deterministic alias: announcements_<spaceLocalpart>_<epochMs>.
      final alias = state['m.room.canonical_alias']?['']?['alias'] as String?;
      expect(alias, isNotNull, reason: 'roomAliasName must produce an alias');
      expect(
        alias,
        startsWith('#${CourseDefaultChatsEnum.announcements.alias}_'),
      );

      // Restricted PL: learners (events_default 50 > users_default 0) cannot
      // post in announcements.
      final powerLevels = state['m.room.power_levels']?[''];
      expect(powerLevels?['events_default'], 50);
      expect(powerLevels?['users_default'], 0);

      // knock_restricted scoped to the course, with an access code.
      final joinRules = state['m.room.join_rules']?[''];
      expect(joinRules?['join_rule'], 'knock_restricted');
      expect(
        (joinRules?['allow'] as List?)
            ?.map((a) => (a as Map)['room_id'])
            .toList(),
        [spaceId],
      );

      // Attached to the course.
      final spaceState = await ContractHarness.serverState(client, spaceId);
      expect(spaceState['m.space.child']?[roomId], isNotNull);
    });

    test('introductions: default PL lets learners post', () async {
      final spaceId = await makeCourseSpace(nameSuffix: 'for-intro');
      final space = client.getRoomById(spaceId);

      final roomId = await space!.addDefaultChat(
        type: CourseDefaultChatsEnum.introductions,
        name: 'Introductions',
      );
      final state = await ContractHarness.serverState(client, roomId);

      final alias = state['m.room.canonical_alias']?['']?['alias'] as String?;
      expect(
        alias,
        startsWith('#${CourseDefaultChatsEnum.introductions.alias}_'),
      );
      expect(state['m.room.power_levels']?['']?['events_default'], 0);
    });
  });
}

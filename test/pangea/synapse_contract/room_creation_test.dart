@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics_access/course_settings_model.dart';
import 'package:fluffychat/features/bot/bot_options_model.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
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

  // A non-empty access code. generateCustomJoinRules swallows a
  // request_room_code failure by omitting the key, so anything weaker than
  // "non-empty string" would pass on a broken code-minting endpoint.
  final validAccessCode = isA<String>().having(
    (c) => c.isNotEmpty,
    'non-empty',
    true,
  );

  setUpAll(() async {
    await ContractHarness.initTestEnvironment();
    // Per-file persona: the four suite files run concurrently and would
    // otherwise share Synapse's per-user rate-limit buckets.
    client = await ContractHarness.loggedIn('contract-creation-a');
  });

  tearDownAll(() async {
    await ContractHarness.dispose(client);
  });

  Future<String> makeCourseSpace({String? nameSuffix}) async {
    final roomId = await client.createPangeaSpace(
      name:
          'Contract Course ${nameSuffix ?? ''} '
          '${DateTime.now().millisecondsSinceEpoch}',
      topic: 'synapse-contract-suite fixture',
      visibility: Visibility.public,
      joinRules: JoinRules.knock,
      spaceChild: 0,
      initialState: [
        // The production serializers, exactly as selected_course_page passes
        // them — a model key rename must fail this suite, not just the app.
        StateEvent(
          type: PangeaEventTypes.coursePlan,
          content: CoursePlanEvent(
            uuid: 'contract-course-uuid',
            l2: 'es',
          ).toJson(),
        ),
        StateEvent(
          type: PangeaEventTypes.courseSettings,
          content: const CourseSettingsModel(
            requireAnalyticsAccess: true,
          ).toJson(),
        ),
      ],
    );
    ContractHarness.trackRoom(client, roomId);
    return roomId;
  }

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
        validAccessCode,
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

      // Custom initial-state events landed byte-equal with the serializers.
      expect(
        state[PangeaEventTypes.coursePlan]?[''],
        CoursePlanEvent(uuid: 'contract-course-uuid', l2: 'es').toJson(),
      );
      expect(
        state[PangeaEventTypes.courseSettings]?[''],
        const CourseSettingsModel(requireAnalyticsAccess: true).toJson(),
      );

      // Topic round-trips (name is trimmed by the extension, not the server).
      expect(
        state['m.room.topic']?['']?['topic'],
        'synapse-contract-suite fixture',
      );
    });
  });

  ActivityPlanModel makeActivity({
    required String activityId,
    String? versionId,
    String? imageURL,
  }) => ActivityPlanModel(
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
    activityId: activityId,
    versionId: versionId,
    imageURL: imageURL,
  );

  group('launchActivitySession (activity session)', () {
    test('the session shape round-trips and attaches to the course', () async {
      final spaceId = await makeCourseSpace(nameSuffix: 'for-session');
      final space = client.getRoomById(spaceId);
      expect(space, isNotNull, reason: 'course space must be synced locally');

      final role = ActivityRole(
        id: 'role-1',
        name: 'speaker',
        goal: null,
        goals: [],
      );

      final roomId = await client.launchActivitySession(
        makeActivity(
          activityId: 'contract-activity-id',
          versionId: 'contract-version-1',
        ),
        role,
        primarySpace: space,
      );
      ContractHarness.trackRoom(client, roomId);
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

      // The pre-claimed role landed with its content intact — an emptied or
      // normalized roles event would break the seat model while isNotNull
      // stayed green.
      // ActivityRolesModel.toJson wraps the map: {'roles': {roleId: {...}}}.
      final roles = state[PangeaEventTypes.activityRole]?[''];
      final roleEntry = (roles?['roles'] as Map?)?['role-1'] as Map?;
      expect(
        roleEntry?['user_id'],
        client.userID,
        reason: 'pre-filled pangea.activity_roles must carry the claim',
      );
      expect(roleEntry?['role'], 'speaker');

      // knock_restricted scoped to the course, access_code intact.
      final joinRules = state['m.room.join_rules']?[''];
      expect(joinRules?['join_rule'], 'knock_restricted');
      expect(
        (joinRules?['allow'] as List?)
            ?.map((a) => (a as Map)['room_id'])
            .toList(),
        contains(spaceId),
      );
      expect(joinRules?['access_code'], validAccessCode);

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

      // The session was shared into the course space. A DETACHED child is an
      // empty-content m.space.child event, so presence alone proves nothing:
      // the via list is what makes the link live (the SDK's spaceChildren
      // getter filters on it too).
      final spaceState = await ContractHarness.serverState(client, spaceId);
      expect(
        spaceState['m.space.child']?[roomId]?['via'] as List?,
        isNotEmpty,
        reason: 'session must be attached (live via) to the launching course',
      );

      // The bot invite is best-effort by design. Only assert it when the bot
      // account exists on THIS homeserver: an off-domain BOT_NAME makes the
      // production invite fail-and-log, which is not a contract break.
      final botId = BotName.byEnvironment;
      final sameDomain =
          botId.split(':').last == client.userID!.split(':').last;
      var botExists = false;
      if (sameDomain) {
        try {
          // Raw request: the SDK's getProfileFromUserId never throws.
          await client.request(
            RequestType.GET,
            '/client/v3/profile/${Uri.encodeComponent(botId)}',
          );
          botExists = true;
        } catch (_) {}
      }
      if (botExists) {
        final botMember = state['m.room.member']?[botId]?['membership'];
        if (botMember == null) {
          // The bot is EVERY run's invite target, so Synapse's per-target
          // rc_invites budget (burst 5, slow refill) can 429 the
          // production invite, which is best-effort and swallowed.
          // Distinguish that environmental case from a broken invite path
          // by probing an invite directly.
          try {
            await client.inviteUser(roomId, botId);
            fail(
              'the launch-time bot invite silently failed although '
              'inviting works — the best-effort invite path is broken',
            );
          } on MatrixException catch (e) {
            if (e.error == MatrixError.M_LIMIT_EXCEEDED) {
              markTestSkipped(
                'bot invite rate-limited (rc_invites per-target budget '
                'across suite runs) — not a contract break',
              );
              return;
            }
            rethrow;
          }
        }
        expect(botMember, 'invite', reason: 'bot should be invited at launch');
      } else {
        markTestSkipped(
          'bot $botId not present on this homeserver — invite assertion '
          'skipped (best-effort by design)',
        );
      }
    });

    test('a session with no course spaces uses plain knock', () async {
      // The other production branch: no matching courses, no primarySpace.
      final roomId = await client.launchActivitySession(
        makeActivity(
          activityId: 'contract-spaceless-id',
          imageURL: 'https://content.pangea.chat/contract-test.png',
        ),
        null,
        primarySpace: null,
      );
      ContractHarness.trackRoom(client, roomId);
      final state = await ContractHarness.serverState(client, roomId);

      final joinRules = state['m.room.join_rules']?[''];
      expect(joinRules?['join_rule'], 'knock');
      expect(
        joinRules?['allow'],
        isNull,
        reason: 'no allow list without course spaces',
      );

      final plan = state[PangeaEventTypes.activityPlan]?[''];
      expect(plan?['activity_id'], 'contract-spaceless-id');
      expect(
        plan?.containsKey('source_course_id'),
        false,
        reason: 'no source course to pin',
      );

      // The avatar initial-state branch.
      expect(
        state['m.room.avatar']?['']?['url'],
        'https://content.pangea.chat/contract-test.png',
      );
    });
  });

  group('createPangeaDirectChat (DM)', () {
    test('the unencrypted DM shape with bot_options round-trips', () async {
      // A fresh invitee each run: startDirectChat reuses an existing DM from
      // m.direct, and the point here is the creation shape.
      final invitee =
          'contract-dm-target-${DateTime.now().millisecondsSinceEpoch}';
      await ContractHarness.loggedIn(invitee).then(ContractHarness.dispose);
      final inviteeId = '@$invitee:${client.userID!.split(':').last}';

      // The production model, exactly as bot_client_extension builds it.
      final botOptions = BotOptionsModel(
        mode: 'directChat',
        targetLanguage: 'es',
        languageLevel: LanguageLevelTypeEnum.a1,
      );

      final roomId = await client.createPangeaDirectChat(
        inviteeId,
        initialState: [
          StateEvent(
            type: PangeaEventTypes.botOptions,
            content: botOptions.toJson(),
          ),
        ],
      );
      ContractHarness.trackRoom(client, roomId);
      final state = await ContractHarness.serverState(client, roomId);

      // Encryption is forced OFF on every Pangea room — the choreographer
      // and bot must be able to read message content.
      expect(
        state['m.room.encryption'],
        isNull,
        reason: 'Pangea DMs must not be encrypted',
      );

      // The bot-options initial state landed byte-equal with the serializer.
      expect(state[PangeaEventTypes.botOptions]?[''], botOptions.toJson());

      // It is a DM: the invitee holds an invite with is_direct.
      final inviteeMember = state['m.room.member']?[inviteeId];
      expect(inviteeMember?['membership'], 'invite');
      expect(inviteeMember?['is_direct'], true);
    });

    test('the plain DM shape (no initial state) round-trips', () async {
      // The most common DM in the app: support/user DMs pass no initial
      // state at all.
      final invitee =
          'contract-dm-plain-${DateTime.now().millisecondsSinceEpoch}';
      await ContractHarness.loggedIn(invitee).then(ContractHarness.dispose);
      final inviteeId = '@$invitee:${client.userID!.split(':').last}';

      final roomId = await client.createPangeaDirectChat(inviteeId);
      ContractHarness.trackRoom(client, roomId);
      final state = await ContractHarness.serverState(client, roomId);

      expect(state['m.room.encryption'], isNull);
      expect(state['m.room.member']?[inviteeId]?['is_direct'], true);
    });
  });

  group('report DM', () {
    test(
      'the reports DM is unencrypted and parented into the course',
      () async {
        // report_message.dart: teacher.startDirectChat(enableEncryption:
        // false) followed by space.setSpaceChild(dmRoomId) — a DM living
        // inside a course space.
        final spaceId = await makeCourseSpace(nameSuffix: 'for-report');
        final teacher =
            'contract-report-t-${DateTime.now().millisecondsSinceEpoch}';
        await ContractHarness.loggedIn(teacher).then(ContractHarness.dispose);
        final teacherId = '@$teacher:${client.userID!.split(':').last}';

        final dmId = await client.startDirectChat(
          teacherId,
          enableEncryption: false,
        );
        ContractHarness.trackRoom(client, dmId);
        await client
            .getRoomById(spaceId)!
            .setSpaceChild(dmId, suggested: false);

        final state = await ContractHarness.serverState(client, dmId);
        expect(state['m.room.encryption'], isNull);
        final spaceState = await ContractHarness.serverState(client, spaceId);
        expect(
          spaceState['m.space.child']?[dmId]?['via'] as List?,
          isNotEmpty,
          reason: 'the reports DM must be reachable through the course space',
        );
      },
    );
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
      ContractHarness.trackRoom(client, roomId);
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
      expect(joinRules?['access_code'], validAccessCode);

      final powerLevels = state['m.room.power_levels']?[''];
      // No users override passed → Synapse's generated creator-100 survives.
      expect((powerLevels?['users'] as Map?)?[client.userID], 100);
      expect(powerLevels?['state_default'], 50);
      final eventLevels = powerLevels?['events'] as Map?;
      expect(eventLevels?[PangeaEventTypes.activityRole], 0);
    });
  });

  group('analytics room', () {
    test('getMyAnalyticsRoom creates the p.analytics shape', () async {
      // A fresh persona so the extension actually CREATES (it returns an
      // existing analytics room when one is local). This drives the real
      // production path — no mirror to drift.
      final learner = await ContractHarness.loggedIn(
        'contract-analytics-${DateTime.now().millisecondsSinceEpoch}',
      );
      addTearDown(() => ContractHarness.dispose(learner));

      final room = await learner.getMyAnalyticsRoom(
        LanguageModel(langCode: 'es', displayName: 'Spanish'),
      );
      expect(room, isNotNull);
      ContractHarness.trackRoom(learner, room!.id);
      final state = await ContractHarness.serverState(learner, room.id);

      // Non-spec keys in m.room.create must survive.
      final create = state['m.room.create']?[''];
      expect(create?['type'], PangeaRoomTypes.analytics);
      expect(create?['lang_code'], 'es');

      // publicChat preset + private visibility: the join rule comes from the
      // initial join_rules event, and the room stays out of the directory.
      expect(state['m.room.join_rules']?['']?['join_rule'], 'knock');
      final visibility = await learner.getRoomVisibilityOnDirectory(room.id);
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
      ContractHarness.trackRoom(client, roomId);
      final state = await ContractHarness.serverState(client, roomId);

      // Deterministic alias: <type.alias>_<spaceLocalpart>_<epochMs>.
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

      // Attached to the course with a live via list (an empty-content
      // m.space.child means detached).
      final spaceState = await ContractHarness.serverState(client, spaceId);
      expect(spaceState['m.space.child']?[roomId]?['via'] as List?, isNotEmpty);
    });

    test('introductions: default PL lets learners post', () async {
      final spaceId = await makeCourseSpace(nameSuffix: 'for-intro');
      final space = client.getRoomById(spaceId);

      final roomId = await space!.addDefaultChat(
        type: CourseDefaultChatsEnum.introductions,
        name: 'Introductions',
      );
      ContractHarness.trackRoom(client, roomId);
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

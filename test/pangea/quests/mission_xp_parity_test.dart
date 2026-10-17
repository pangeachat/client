import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_settings_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/features/user/user_model.dart' as pangea;
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../activity_session_fixtures.dart';
import '../analytics_data/analytics_fixtures.dart';

/// The shared Mission XP parity fixture (`mission-xp-parity.json`, byte-identical
/// in admin-dash-api's tests/fixtures): each case is a learner's stored uses,
/// blocked constructs, saved and unsaved sessions and a course outline, with
/// the figures the app must show. This runs it through the real client code:
/// [AnalyticsDataService.getUses] (capped and blocked filtering, merge table)
/// over a real analytics store, the [MissionXpCache] split, the session rooms'
/// [QuestsClientExtension.userXpBreakdownByActivity] and goal checkmarks,
/// [TeacherModeModel] on a course room, and [resolveProgression].
///
/// A disagreement here means the server port differs from the app: fix the
/// port, never this fixture.
const _userId = testSessionUserId;
const _courseRoomId = '!course:fakeServer.notExisting';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);
  final Client _client;
  late AnalyticsDataService service;

  @override
  Client get client => _client;

  @override
  AnalyticsDataService? get analyticsServiceIfExists => service;
}

Event _state(Room room, String type, Map<String, dynamic> content, int n) =>
    Event(
      type: type,
      content: content,
      stateKey: '',
      senderId: _userId,
      eventId: '\$${type}_${room.id}_$n',
      originServerTs: DateTime.utc(2026, 1, 1, 12),
      room: room,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final fixture =
      jsonDecode(
            File(
              'test/pangea/quests/fixtures/mission-xp-parity.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final cases = (fixture['cases'] as List)
      .cast<Map<String, dynamic>>()
      .where((c) => c['adapiOnlyCase'] != true)
      .toList();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('mission_xp_parity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {
            'language_code': testLang,
            'language_name': 'Spanish',
            'l2_support': 'full',
          },
          {'language_code': 'en', 'language_name': 'English'},
        ],
      }),
    });
    await PLanguageStore.initialize();
  });

  tearDown(() {
    QuestRepo.debugDisplayL1 = null;
    MissionXpCache.instance.seed();
  });

  var storeSeq = 0;

  /// A logged-in client with the learner's own analytics room (carrying the
  /// blocked constructs), a store seeded with [uses], and an initialised
  /// service over it — the state the app reads from.
  Future<(Client, AnalyticsDataService)> analyticsFor(
    Map<String, dynamic> testCase,
  ) async {
    final api = FakeMatrixApi();
    final client = Client(
      'testclient',
      httpClient: api,
      database: await MatrixSdkDatabase.init(
        'mission_xp_parity',
        database: await databaseFactoryFfi.openDatabase(
          ':memory:',
          options: OpenDatabaseOptions(singleInstance: false),
        ),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    api.api['GET']!['/.well-known/matrix/client'] = (_) => {};
    api.api['PUT']!['/client/unstable/uk.tcpip.msc4133/profile/'
        '%40test%3AfakeServer.notExisting/'
        '${PangeaEventTypes.profileAnalytics}'] = (_) =>
        {};
    await client.checkHomeserver(Uri.parse('https://fakeserver.notexisting'));
    await client.login(
      LoginType.mLoginToken,
      identifier: AuthenticationUserIdentifier(user: 'test'),
      password: '1234',
    );
    client.accountData[UserConstants.userProfile] = BasicEvent(
      type: UserConstants.userProfile,
      content: pangea.Profile(
        userSettings: pangea.UserSettings(
          sourceLanguage: 'en',
          targetLanguage: testLang,
        ),
      ).toJson(),
    );

    final matrixState = _FakeMatrixState(client);
    MatrixState.pangeaController = PangeaController(matrixState: matrixState);
    MatrixState.pangeaController.userController.setPublicProfile(
      PublicProfileModel(analytics: AnalyticsProfileModel()),
      userId: client.userID,
    );

    // The learner's own analytics room, canonical, for Spanish, carrying the
    // blocked constructs as pangea.analytics_settings.
    final analyticsRoom = Room(
      id: '!analytics:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
    );
    analyticsRoom.setState(
      _state(analyticsRoom, EventTypes.RoomCreate, {
        'creator': _userId,
        'type': PangeaRoomTypes.analytics,
        ModelKey.langCode: testLang,
      }, 0),
    );
    analyticsRoom.setState(
      _state(
        analyticsRoom,
        PangeaEventTypes.analyticsSettings,
        AnalyticsSettingsModel(
          blockedConstructs: {
            for (final b in (testCase['blocked'] as List))
              ConstructIdentifier.fromJson((b as Map).cast<String, dynamic>()),
          },
        ).toJson(),
        1,
      ),
    );
    client.rooms.add(analyticsRoom);

    final db = await freshDatabase(name: 'mission_xp_parity_${storeSeq++}');
    await db.updateUserID(client.userID!);
    await db.updateCurrentLanguage(testLang);
    await db.updateAnalyticsRoomId(analyticsRoom.id);
    await db.updateLocalAnalytics([
      for (final u in (testCase['uses'] as List))
        OneConstructUse.fromJson((u as Map).cast<String, dynamic>()),
    ], testLang);

    final service = AnalyticsDataService(
      client,
      databaseBuilder: (_) async => db,
    );
    matrixState.service = service;
    await service.initCompleter.future.timeout(const Duration(seconds: 20));
    expect(service.initError, isNull);
    return (client, service);
  }

  /// The learner's sessions as rooms: a left room is absent from the client,
  /// an unsaved one has no archive time, the goals awarded to the learner's
  /// role are [ownGoals] of its goals.
  void addSessions(Client client, List<Map<String, dynamic>> sessions) {
    for (final s in sessions) {
      final membership = s['membership'] as String;
      if (membership == 'leave') continue;
      final goals = s['ownGoals'] as int;
      final room = activitySessionRoom(
        client,
        roomId: s['roomId'] as String,
        activityId: s['activityId'] as String,
        roles: {
          _userId: ActivityRoleModel(
            id: 'r1',
            userId: _userId,
            archivedAt: s['archivedAt'] == null
                ? null
                : DateTime.parse(s['archivedAt'] as String),
          ),
        },
        awarded: {
          'r1': [for (var n = 1; n <= goals; n++) 'slug-$n'],
        },
      );
      room.membership = membership == 'invite'
          ? Membership.invite
          : Membership.join;
      client.rooms.add(room);
    }
  }

  ActivityPlanModel planWith(String activityId, List<String> lemmas) {
    final base = twoRoleActivityPlan(activityId: activityId);
    return ActivityPlanModel(
      req: base.req,
      title: base.title,
      learningObjective: base.learningObjective,
      instructions: base.instructions,
      vocab: [for (final l in lemmas) Vocab(lemma: l, pos: 'noun')],
      activityId: activityId,
      roles: base.roles,
    );
  }

  /// The case's course as the app builds its outline: each Can-Do a group
  /// whose first activity carries the Can-Do's word list, so the group's
  /// words (and the outline's `lemmasByLo`) are the fixture's.
  QuestOutline outlineOf(Map<String, dynamic> outline) {
    final loIds = (outline['orderedLoIds'] as List).cast<String>();
    final byLo = (outline['activityIdsByLo'] as Map).cast<String, dynamic>();
    final lemmas = (outline['lemmasByLo'] as Map).cast<String, dynamic>();
    return QuestOutline(
      quest: QuestPlan(
        id: 'q1',
        name: '',
        description: '',
        targetLanguage: testLang,
        sequence: [
          for (final lo in loIds)
            QuestObjectiveStep(
              objective: LearningObjective(id: lo, objective: lo),
              wasMinted: false,
            ),
        ],
      ),
      groups: [
        for (final lo in loIds)
          QuestObjectiveGroup(
            objective: LearningObjective(id: lo, objective: lo),
            activities: [
              for (final (i, id) in (byLo[lo] as List).cast<String>().indexed)
                QuestActivity(
                  activityId: id,
                  plan: planWith(
                    id,
                    i == 0 ? (lemmas[lo] as List).cast<String>() : const [],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Room courseRoom(Client client, Map<String, dynamic>? teacherMode) {
    final room = Room(
      id: _courseRoomId,
      client: client,
      membership: Membership.join,
    );
    if (teacherMode != null) {
      room.setState(_state(room, PangeaEventTypes.teacherMode, teacherMode, 0));
    }
    return room;
  }

  for (final testCase in cases) {
    final name = testCase['name'] as String;
    final expected = (testCase['expected'] as Map).cast<String, dynamic>();

    test('case $name: client figures equal the fixture', () async {
      QuestRepo.debugDisplayL1 = 'en';
      final (client, service) = await analyticsFor(testCase);
      addTearDown(client.dispose);

      // 1. getUses over the real store: capped, blocked and invalid filtered.
      final uses = await service.getUses(testLang, filterCapped: true);
      expect(uses, isNotEmpty);

      // 2. The shared cache's real refresh splits them by room and lemma.
      await MissionXpCache.instance.refresh();
      final cache = MissionXpCache.instance;
      expect(cache.chatXpByRoom, _ints(expected['chatXpByRoom']));
      expect(cache.practiceXpByRoom, _ints(expected['practiceXpByRoom']));
      expect(cache.practiceXpByLemma, _ints(expected['practiceXpByLemma']));

      // 3. The learner's session rooms: XP by source and goal checkmarks.
      addSessions(client, (testCase['sessions'] as List).cast());
      final byActivity = client.userXpBreakdownByActivity(
        chatXpByRoom: cache.chatXpByRoom,
        practiceXpByRoom: cache.practiceXpByRoom,
      );
      final wantByActivity = (expected['xpByActivity'] as Map)
          .cast<String, dynamic>();
      expect({
        for (final e in byActivity.entries)
          e.key: {
            'chat': e.value.chat,
            'goals': e.value.goals,
            'practice': e.value.practice,
          },
      }, wantByActivity);
      expect(
        client.userStarsByActivity,
        _ints(expected['bestDiamondsByActivity']),
      );

      // 4. The course's target, from the course room's teacher mode.
      final room = courseRoom(
        client,
        (testCase['teacherMode'] as Map?)?.cast<String, dynamic>(),
      );
      final target =
          room.teacherMode.xpToCompleteObjective ??
          kDefaultXpToCompleteObjective;
      expect(target, expected['target']);

      // 5. Mission XP, completion and the star summary.
      final outline = outlineOf(
        (testCase['outline'] as Map).cast<String, dynamic>(),
      );
      final progression = resolveProgression(
        outlines: [outline.toCourseLoOutline(xpToComplete: target)],
        xpByActivity: client.userXpByActivity(cache.creditedXpByRoom),
        practiceXpByLemma: cache.practiceXpByLemma,
      ).forCourse('q1')!;
      final wantMissions = (expected['missions'] as Map)
          .cast<String, dynamic>();
      expect(progression.rollup.keys.toSet(), wantMissions.keys.toSet());
      for (final entry in wantMissions.entries) {
        final want = (entry.value as Map).cast<String, dynamic>();
        final group = outline.groups.firstWhere(
          (g) => g.objective.id == entry.key,
        );
        final breakdown = client.missionXpBreakdown(
          group,
          byActivity: byActivity,
        );
        final rollup = progression.rollup[entry.key]!;
        expect(
          {
            'chat': breakdown.chat,
            'goals': breakdown.goals,
            'practice': breakdown.practice,
            'xp': rollup.xp,
            'satisfied': rollup.satisfied,
          },
          want,
          reason: '${entry.key} of case $name',
        );
        // The breakdown and the rollup are one number.
        expect(breakdown.total, rollup.xp);
      }
      final wantStars = (expected['starSummary'] as Map)
          .cast<String, dynamic>();
      expect({
        'earned': progression.starSummary.earned,
        'total': progression.starSummary.total,
      }, wantStars);
    });
  }

  group('the course target from the teacher-mode state', () {
    final targets = (fixture['targets'] as List).cast<Map<String, dynamic>>();
    for (final (i, t) in targets.indexed) {
      test('target case $i: ${jsonEncode(t['teacherMode'])}', () async {
        final client = Client(
          'testclient',
          httpClient: FakeMatrixApi(),
          database: await MatrixSdkDatabase.init(
            'mission_xp_targets',
            database: await databaseFactoryFfi.openDatabase(
              ':memory:',
              options: OpenDatabaseOptions(singleInstance: false),
            ),
            sqfliteFactory: databaseFactoryFfi,
          ),
        );
        addTearDown(client.dispose);
        final room = courseRoom(
          client,
          (t['teacherMode'] as Map?)?.cast<String, dynamic>(),
        );
        expect(
          room.teacherMode.xpToCompleteObjective ??
              kDefaultXpToCompleteObjective,
          t['expected'],
        );
      });
    }
  });
}

Map<String, int> _ints(Object? raw) => {
  for (final e in (raw as Map).entries) e.key as String: e.value as int,
};

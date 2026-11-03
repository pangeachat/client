import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/can_do_progress.dart';
import 'package:fluffychat/features/quests/course_language_scope.dart';
import 'package:fluffychat/features/quests/course_progress_event.dart';
import 'package:fluffychat/features/quests/course_progress_writer.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../analytics_data/analytics_fixtures.dart';
import '../get_test_client.dart';

/// The course progress check while a saved session's plan is loading
/// (ADMIN-DASH-API-1W). A session the learner saved before saves were filed
/// by language counts once its plan loads, and a loaded plan leaves the cache
/// after an hour; a check in between saw its Missions without its XP and
/// wrote that, and the check after the plan came back wrote it back, every
/// hour the app stayed open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Before the plan repo is touched (the session's plan getter reaches it):
  // its cache builds a GetStorage container, which asks path_provider at once.
  final tempDir = Directory.systemTemp.createTempSync('progress_plan_wait');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );

  final es = LanguageModel(langCode: 'es', displayName: 'Spanish');
  const userId = '@test:fakeServer.notExisting';
  const questId = 'quest-1';
  const missionId = 'lo-1';
  const activityId = 'activity-1';
  const courseRoomId = '!course:fakeServer.notExisting';
  const sessionId = '!session:fakeServer.notExisting';
  // FakeMatrixApi answers state writes for this room only.
  const analyticsRoomId = '!1234:fakeServer.notExisting';

  final cache = MissionXpCache.instance;
  final analytics = _Analytics()..loaded = 'es';
  late Client client;

  setUpAll(() async {
    await GetStorage.init('activity_plan_storage');
    PackageInfo.setMockInitialValues(
      appName: 'Pangea Chat',
      packageName: 'com.talktolearn.chat',
      version: '5.0.18',
      buildNumber: '1',
      buildSignature: '',
    );
    MatrixState.pangeaController = _Controller(_Users(es), _Matrix(analytics));
  });

  setUp(() async {
    client = await getTestClient();
    QuestRepo.resetOutlineCacheForTest();
    QuestRepo.debugDisplayL1 = 'en';
    FakeMatrixApi.calledEndpoints.clear();
  });

  tearDown(() async {
    QuestRepo.debugBuildOutline = null;
    QuestRepo.debugDisplayL1 = null;
    QuestRepo.resetOutlineCacheForTest();
    await client.dispose();
  });

  Event stateEvent(
    Room room, {
    required String type,
    required Map<String, dynamic> content,
    String stateKey = '',
  }) => Event(
    type: type,
    content: content,
    stateKey: stateKey,
    senderId: userId,
    eventId: '\$${type}_$stateKey',
    originServerTs: DateTime.utc(2026, 10, 1, 12),
    room: room,
  );

  ActivityPlanModel plan() => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: 'food',
      mode: 'Roleplay',
      objective: 'order food',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'es',
      numberOfParticipants: 2,
    ),
    title: 'At the market',
    learningObjective: 'order food',
    instructions: 'i',
    vocab: [Vocab(lemma: 'casa', pos: 'noun')],
    activityId: activityId,
    roles: const {},
  );

  void stubOutline() {
    QuestRepo.debugBuildOutline = (id, {courseRoomId}) async => Result.value(
      QuestOutline(
        quest: const QuestPlan(
          id: questId,
          name: 'Quest',
          description: '',
          targetLanguage: 'es',
          sequence: [
            QuestObjectiveStep(
              objective: LearningObjective(id: missionId, objective: 'm'),
              wasMinted: false,
            ),
          ],
        ),
        groups: [
          QuestObjectiveGroup(
            objective: const LearningObjective(id: missionId, objective: 'm'),
            activities: [QuestActivity(activityId: activityId, plan: plan())],
          ),
        ],
      ),
    );
  }

  void registerCourse() {
    final space = Room(
      id: courseRoomId,
      client: client,
      membership: Membership.join,
    );
    space.setState(
      stateEvent(
        space,
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
      ),
    );
    space.setState(
      stateEvent(
        space,
        type: PangeaEventTypes.coursePlan,
        content: CoursePlanEvent(uuid: questId, l2: 'es').toJson(),
      ),
    );
    client.rooms.add(space);
  }

  /// A saved session from before saves were filed by language: its state
  /// holds only a reference to its plan, which loads from the backend.
  void registerUnfiledSession() {
    final room = Room(
      id: sessionId,
      client: client,
      membership: Membership.join,
    );
    room.setState(
      stateEvent(
        room,
        type: EventTypes.RoomCreate,
        content: {'type': '${PangeaRoomTypes.activitySession}:$activityId'},
      ),
    );
    room.setState(
      stateEvent(
        room,
        type: PangeaEventTypes.activityPlan,
        content: {
          ActivitySessionConstants.activityId: activityId,
          ActivitySessionConstants.versionId: 'v1',
        },
      ),
    );
    room.setState(
      stateEvent(
        room,
        type: PangeaEventTypes.activityRole,
        content: ActivityRolesModel({
          'r1': ActivityRoleModel(
            id: 'r1',
            userId: userId,
            role: 'Buyer',
            finishedAt: DateTime.utc(2026, 5, 1, 12),
            archivedAt: DateTime.utc(2026, 5, 1, 12),
          ),
        }).toJson(),
      ),
    );
    client.rooms.add(room);
  }

  /// The learner's analytics room, holding the course's record at [xp].
  Room analyticsRoomWithRecord(int xp) {
    final room = Room(id: analyticsRoomId, client: client);
    room.setState(
      stateEvent(
        room,
        type: PangeaEventTypes.courseProgress,
        stateKey: courseRoomId,
        content: CourseProgressEvent(
          computedAt: DateTime.utc(2026, 11, 2, 10, 32),
          appVersion: '5.0.18+1',
          xpToComplete: kDefaultXpToCompleteObjective,
          canDos: {
            missionId: CanDoProgress(
              xp: xp,
              breakdown: MissionXpBreakdown(practice: xp),
              completed: false,
            ),
          },
        ).toJson(),
      ),
    );
    return room;
  }

  /// 300 XP earned in the session and 50 practising the Mission's word
  /// outside any session.
  Future<void> readXp() async {
    analytics.store['es'] = [
      use(lemma: 'mesa', xp: 300, ts: at(0), roomId: sessionId),
      use(lemma: 'casa', xp: 50, ts: at(1)),
    ];
    cache.ensureWired();
    for (var i = 0; i < 3; i++) {
      await cache.refresh();
      await Future<void>.delayed(Duration.zero);
    }
    expect(cache.hasReadFor('es'), isTrue);
  }

  Iterable<String> progressWrites() => FakeMatrixApi.calledEndpoints.keys.where(
    (path) => path.contains('/state/${PangeaEventTypes.courseProgress}'),
  );

  test('the session waits for its plan, which the check knows', () async {
    registerUnfiledSession();
    expect(client.savedSessionActivitiesAwaitingPlan, {activityId});
    final session = client.getRoomById(sessionId)!;
    expect(
      CourseLanguageScope.savedSessionAwaitingPlan(session, {sessionId}),
      isFalse,
      reason: 'a session filed under the language needs no plan',
    );
  });

  test('a lower figure is not written while the plan loads', () async {
    stubOutline();
    registerCourse();
    registerUnfiledSession();
    await readXp();
    // Written while the plan was loaded: the session's 300 and the word's 50.
    final analyticsRoom = analyticsRoomWithRecord(350);

    await CourseProgressWriter(
      readUses: (_) async => const [],
    ).update(analyticsRoom, 'es');

    expect(progressWrites(), isEmpty);
  });

  test('a higher figure is written while the plan loads', () async {
    stubOutline();
    registerCourse();
    registerUnfiledSession();
    await readXp();
    final analyticsRoom = analyticsRoomWithRecord(20);

    await CourseProgressWriter(
      readUses: (_) async => const [],
    ).update(analyticsRoom, 'es');

    expect(progressWrites(), hasLength(1));
  });
}

class _Analytics implements AnalyticsDataService {
  @override
  final AnalyticsUpdateDispatcher updateDispatcher = _Dispatcher();

  @override
  Completer<void> initCompleter = Completer<void>()..complete();

  @override
  Object? initError;

  @override
  bool get hasInitError => initError != null;

  String? loaded;

  @override
  String? get initializedLanguage => loaded;

  final Map<String, List<OneConstructUse>> store = {};

  @override
  Future<List<OneConstructUse>> getUses(
    String language, {
    int? count,
    String? roomId,
    DateTime? since,
    List<ConstructUseTypeEnum>? types,
    bool filterCapped = true,
  }) async => store[language] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Dispatcher implements AnalyticsUpdateDispatcher {
  @override
  final StreamController<AnalyticsStreamUpdate> constructUpdateStream =
      StreamController<AnalyticsStreamUpdate>.broadcast();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Users implements UserController {
  _Users(this.userL2);

  @override
  LanguageModel? userL2;

  @override
  String? get userL1Code => 'en';

  @override
  final StreamController<LanguageUpdate> languageStream =
      StreamController<LanguageUpdate>.broadcast();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Matrix implements MatrixState {
  _Matrix(this.analytics);

  final AnalyticsDataService analytics;

  @override
  AnalyticsDataService? get analyticsServiceIfExists => analytics;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_Matrix';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Controller implements PangeaController {
  _Controller(this.userController, this.matrixState);

  @override
  final UserController userController;

  @override
  final MatrixState matrixState;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

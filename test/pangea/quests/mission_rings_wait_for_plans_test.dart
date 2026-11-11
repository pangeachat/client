import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:async/async.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' hide Profile, Result;

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';

/// #9606 — the course page's Mission rings stop shimmering only once the
/// plans of the saved sessions they count have loaded. A saved session's
/// goals come from its plan, and so does whether a session saved before saves
/// were filed by language counts at all, so a ring drawn before its plan
/// landed grew a moment after the shimmer ended.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Before the plan repo is touched: its cache builds a GetStorage container,
  // which asks path_provider at once.
  final tempDir = Directory.systemTemp.createTempSync('rings_plan_wait');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );

  const userId = '@test:fakeServer.notExisting';
  const questId = 'quest-1';
  const missionId = 'lo-1';
  const courseRoomId = '!course:fakeServer.notExisting';
  const sessionId = '!session:fakeServer.notExisting';
  const sessionXp = 300;

  late Client client;
  // Each test reads a plan nothing has cached yet: the repo keeps plans on
  // disk across tests.
  var run = 0;
  late String activityId;

  setUpAll(() async {
    MatrixState.pangeaController = _Controller();
    dotenv.testLoad(mergeWith: {'CHOREO_API': 'https://choreo.test'});
    await GetStorage.init('env_override');
    await GetStorage.init('activity_plan_storage');
  });

  setUp(() async {
    activityId = 'rings-plan-${run++}';
    client = await getTestClient();
    ActivityPlanRepo.instance.resetForTesting();
    QuestRepo.resetOutlineCacheForTest();
    QuestRepo.debugDisplayL1 = 'en';
    MissionXpCache.instance.seed(xpByRoom: {sessionId: sessionXp});
  });

  tearDown(() async {
    QuestRepo.debugBuildOutline = null;
    QuestRepo.debugDisplayL1 = null;
    QuestRepo.resetOutlineCacheForTest();
    MissionXpCache.instance.seed();
    ActivityPlanRepo.instance.resetForTesting();
    await client.dispose();
  });

  Event stateEvent(
    Room room, {
    required String type,
    required Map<String, dynamic> content,
  }) => Event(
    type: type,
    content: content,
    stateKey: '',
    senderId: userId,
    eventId: '\$${type}_${room.id}',
    originServerTs: DateTime.utc(2026, 11, 1, 12),
    room: room,
  );

  ActivityPlanModel outlinePlan(String id) => ActivityPlanModel(
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
    vocab: const [],
    activityId: id,
  );

  /// The course's one Mission over [activityId].
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
            activities: [
              QuestActivity(
                activityId: activityId,
                plan: outlinePlan(activityId),
              ),
            ],
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

  /// A saved session of [activity] whose state holds only a reference to its
  /// plan, which loads from the backend. Not filed under a language, so it
  /// counts only once its plan says it is Spanish; its one awarded goal
  /// counts only once the plan lists it for the learner's role.
  void registerSavedSession(String activity, {String roomId = sessionId}) {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    room.setState(
      stateEvent(
        room,
        type: EventTypes.RoomCreate,
        content: {'type': '${PangeaRoomTypes.activitySession}:$activity'},
      ),
    );
    room.setState(
      stateEvent(
        room,
        type: PangeaEventTypes.activityPlan,
        content: {
          ActivitySessionConstants.activityId: activity,
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
            finishedAt: DateTime.utc(2026, 11, 1, 12),
            archivedAt: DateTime.utc(2026, 11, 1, 12),
          ),
        }).toJson(),
      ),
    );
    room.setState(
      stateEvent(
        room,
        type: PangeaEventTypes.orchestratorAwardedGoals,
        content: const OrchestratorAwardedGoals(
          awards: {
            'r1': ['g1'],
          },
        ).toJson(),
      ),
    );
    client.rooms.add(room);
  }

  /// The batch read's answer: [activity]'s Spanish plan, with goal `g1` for
  /// the learner's role.
  http.Response planFound(String activity) => http.Response(
    jsonEncode({
      'activities': {
        activity: {
          'plan': {
            'activity_id': activity,
            'l2': 'es',
            'user_id': '@owner:fakeServer.notExisting',
            'roles': [
              {'role_id': 'r1', 'name': 'Buyer'},
            ],
            'goals': [
              {
                'id': 'g1',
                'goal': 'Order a coffee',
                'role_ids': ['r1'],
              },
            ],
          },
          'l1': 'en',
          'version_id': 'v1',
        },
      },
      'removed': [],
      'unavailable': [],
    }),
    200,
  );

  /// Runs [body] against a plan backend that answers the batch read only
  /// once [answer] completes.
  Future<void> withPlanBackend(
    Future<http.Response> answer,
    Future<void> Function() body,
  ) => http.runWithClient(
    body,
    () => MockClient(
      (request) => request.url.path.endsWith('/v2/activity/batch')
          ? answer
          : Future.value(http.Response('', 404)),
    ),
  );

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  /// Waits for [done], failing after [timeout].
  Future<void> until(bool Function() done, {String? reason}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail(reason ?? 'timed out');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('the rings shimmer while a saved session\'s plan loads, and draw '
      'with its XP once it lands', () async {
    stubOutline();
    registerCourse();
    registerSavedSession(activityId);
    final answer = Completer<http.Response>();

    await withPlanBackend(answer.future, () async {
      final loader = QuestObjectivesLoader(client: client);
      addTearDown(loader.dispose);
      await loader.loadOutline(questId, courseRoomId: courseRoomId);
      await settle();

      expect(loader.hasResolvedProgress, isTrue);
      expect(
        loader.missionProgress(missionId)?.xp,
        0,
        reason: 'the session counts only once its plan says it is Spanish',
      );
      expect(
        loader.progressLoading,
        isTrue,
        reason: 'drawn now, the ring would grow when the plan lands',
      );

      var published = 0;
      loader.progression.addListener(() => published++);
      answer.complete(planFound(activityId));
      await until(() => !loader.progressLoading);

      expect(
        loader.missionProgress(missionId)?.xp,
        sessionXp + kGoalXp,
        reason: 'the shimmer ends on the XP the plan brings, not before it',
      );
      expect(
        published,
        greaterThan(0),
        reason: 'the course page rebuilds on the shared progression',
      );
    });
  });

  test('a plan read that fails ends the wait', () async {
    stubOutline();
    registerCourse();
    registerSavedSession(activityId);
    final answer = Completer<http.Response>();

    await withPlanBackend(answer.future, () async {
      final loader = QuestObjectivesLoader(client: client);
      addTearDown(loader.dispose);
      await loader.loadOutline(questId, courseRoomId: courseRoomId);
      await settle();
      expect(loader.progressLoading, isTrue);

      var published = 0;
      loader.progression.addListener(() => published++);
      answer.complete(http.Response('', 503));
      await until(
        () => !loader.progressLoading,
        reason:
            'a failed read notifies no one, and must not leave the rings '
            'shimmering',
      );

      expect(published, greaterThan(0));
      expect(loader.missionProgress(missionId)?.xp, 0);
    });
  });

  test('a plan this course does not count does not hold its rings', () async {
    stubOutline();
    registerCourse();
    registerSavedSession(
      '$activityId-elsewhere',
      roomId: '!elsewhere:fakeServer.notExisting',
    );
    final answer = Completer<http.Response>();

    await withPlanBackend(answer.future, () async {
      final loader = QuestObjectivesLoader(client: client);
      addTearDown(loader.dispose);
      await loader.loadOutline(questId, courseRoomId: courseRoomId);
      await settle();

      expect(loader.hasResolvedProgress, isTrue);
      expect(loader.progressLoading, isFalse);
      answer.complete(http.Response('', 503));
    });
  });
}

class _Users implements UserController {
  @override
  LanguageModel? get userL2 =>
      LanguageModel(langCode: 'es', displayName: 'Spanish');

  @override
  String? get userL1Code => 'en';

  @override
  String get accessToken => 'test-token';

  @override
  final StreamController<LanguageUpdate> languageStream =
      StreamController<LanguageUpdate>.broadcast();

  @override
  final StreamController<Profile> settingsUpdateStream =
      StreamController<Profile>.broadcast();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// No analytics service, so the XP cache stays unwired and holds what the
/// tests seed.
class _Matrix implements MatrixState {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_Matrix';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Controller implements PangeaController {
  @override
  final UserController userController = _Users();

  @override
  final MatrixState matrixState = _Matrix();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

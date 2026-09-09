import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../get_test_client.dart';

/// #8915 — the course panel's star counts were resolved once, when the outline
/// loaded, and never again. A star earned while the panel was open therefore
/// showed the pre-award number (2/4 under an activity card already drawing
/// three filled stars) until the learner left the page and came back. The
/// rollup is read from session-room state the client already holds, so it
/// re-resolves on the same rate-limited room-sync tick the world map and the
/// objectives list recompute on.
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const questId = 'quest-1';
  const missionId = 'lo-1';
  const activityId = 'activity-1';
  const courseRoomId = '!course:fakeServer.notExisting';
  const sessionId = '!session:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
    QuestRepo.resetOutlineCacheForTest();
    QuestRepo.debugDisplayL1 = 'en';
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
    originServerTs: DateTime.utc(2026, 1, 1, 12),
    room: room,
  );

  ActivityRoleGoal goal(int n) =>
      ActivityRoleGoal(id: 'g$n', goalSlug: 'slug-$n', description: 'goal $n');

  /// Two roles of three goals each — the uniform-per-role shape generation
  /// produces, so the Mission's earnable ceiling is three.
  ActivityPlanModel plan() => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: 'directions',
      mode: 'Roleplay',
      objective: 'ask for directions',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'de',
      numberOfParticipants: 2,
    ),
    title: 'Old Town Directions',
    learningObjective: 'ask for directions',
    instructions: 'i',
    vocab: const [],
    activityId: activityId,
    roles: {
      'r1': ActivityRole(
        id: 'r1',
        name: 'Local',
        goal: null,
        goals: [goal(1), goal(2), goal(3)],
      ),
      'r2': ActivityRole(
        id: 'r2',
        name: 'Visitor',
        goal: null,
        goals: [goal(4), goal(5), goal(6)],
      ),
    },
  );

  /// The joined course space the panel is showing, carrying the quest uuid the
  /// outline resolves from.
  void registerCourseSpace() {
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
        content: CoursePlanEvent(uuid: questId, l2: 'de').toJson(),
      ),
    );
    client.rooms.add(space);
  }

  /// The learner's session room for the course's one activity, seated in
  /// role `r1`. Stars are that role's awarded goals.
  Room registerSession() {
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
        content: plan().toJson(),
      ),
    );
    room.setState(
      stateEvent(
        room,
        type: PangeaEventTypes.activityRole,
        content: ActivityRolesModel({
          'r1': ActivityRoleModel(id: 'r1', userId: userId, role: 'Local'),
        }).toJson(),
      ),
    );
    client.rooms.add(room);
    return room;
  }

  void awardGoals(Room session, List<String> goalIds) => session.setState(
    stateEvent(
      session,
      type: PangeaEventTypes.orchestratorAwardedGoals,
      content: OrchestratorAwardedGoals(awards: {'r1': goalIds}).toJson(),
    ),
  );

  /// A room-update sync — what an orchestrator award arrives on.
  void emitRoomSync() => client.onSync.add(
    SyncUpdate(
      nextBatch: 'star-award',
      rooms: RoomsUpdate(join: {sessionId: JoinedRoomUpdate()}),
    ),
  );

  test('a star awarded while the panel is open updates its Mission count '
      'without a reload', () async {
    QuestRepo.debugBuildOutline = (id, {courseRoomId}) async => Result.value(
      QuestOutline(
        quest: const QuestPlan(
          id: questId,
          name: 'Quest',
          description: '',
          targetLanguage: 'de',
          sequence: [
            QuestObjectiveStep(
              objective: LearningObjective(
                id: missionId,
                objective: 'Can ask for directions.',
              ),
              wasMinted: false,
            ),
          ],
        ),
        groups: [
          QuestObjectiveGroup(
            objective: const LearningObjective(
              id: missionId,
              objective: 'Can ask for directions.',
            ),
            activities: [QuestActivity(activityId: activityId, plan: plan())],
          ),
        ],
      ),
    );

    registerCourseSpace();
    final session = registerSession();
    awardGoals(session, ['g1', 'g2']);

    final loader = QuestObjectivesLoader(client: client);
    addTearDown(loader.dispose);
    await loader.loadOutline(questId, courseRoomId: courseRoomId);

    // The load-time rollup: two of the three stars this Mission can offer.
    expect(loader.missionProgress(missionId)?.stars, 2);
    expect(loader.missionProgress(missionId)?.threshold, 3);
    expect(loader.questStars?.earned, 2);

    // The third star lands as room state on the session room, and the panel
    // stays mounted — this is the moment the count used to freeze.
    awardGoals(session, ['g1', 'g2', 'g3']);
    emitRoomSync();
    // The rate limiter lets the first tick straight through; a microtask hop
    // is all the stream needs to deliver it.
    await Future<void>.delayed(Duration.zero);

    expect(loader.missionProgress(missionId)?.stars, 3);
    expect(loader.questStars?.earned, 3);
    expect(loader.missionProgress(missionId)?.satisfied, isTrue);
  });

  test('a sync before any outline has loaded publishes nothing — no course '
      'shows a denominator it has not resolved', () async {
    registerCourseSpace();
    final session = registerSession();
    awardGoals(session, ['g1']);

    final loader = QuestObjectivesLoader(client: client);
    addTearDown(loader.dispose);

    emitRoomSync();
    await Future<void>.delayed(Duration.zero);

    expect(loader.hasResolvedProgress, isFalse);
    expect(loader.questStars, isNull);
  });
}

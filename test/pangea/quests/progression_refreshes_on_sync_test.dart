import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../get_test_client.dart';

/// #8915 — the course panel's progress was resolved once, when the outline
/// loaded, and never again, so a change while the panel was open showed the
/// stale number until the learner left the page and came back. A Mission's
/// XP (#9420) has two live inputs: the session's construct XP from the shared
/// [MissionXpCache], and the sparkle bonus read from session-room state — a
/// goal awarded as room state raises the session's XP by [kSparkleXpBonus],
/// so the rollup re-resolves on the same rate-limited room-sync tick the world
/// map and the objectives list recompute on, and on every XP-cache change.
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
    MissionXpCache.instance.seed();
  });

  tearDown(() async {
    QuestRepo.debugBuildOutline = null;
    QuestRepo.debugDisplayL1 = null;
    QuestRepo.resetOutlineCacheForTest();
    MissionXpCache.instance.seed();
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
  /// produces; each goal awarded to the learner's role is one sparkle.
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
  /// role `r1`. Sparkles are that role's awarded goals.
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

  /// The course's one quest outline: a single Mission over the single
  /// activity, at the default 300 XP threshold.
  void stubOutline() {
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
  }

  test('a sparkle awarded while the panel is open updates its Mission XP '
      'without a reload', () async {
    stubOutline();

    registerCourseSpace();
    final session = registerSession();
    MissionXpCache.instance.seed(xpByRoom: {sessionId: 250});

    final loader = QuestObjectivesLoader(client: client);
    addTearDown(loader.dispose);
    await loader.loadOutline(questId, courseRoomId: courseRoomId);

    // The load-time rollup: the session's XP, no sparkles yet.
    expect(loader.missionProgress(missionId)?.xp, 250);
    expect(loader.missionProgress(missionId)?.threshold, 300);
    expect(loader.missionProgress(missionId)?.satisfied, isFalse);
    expect(loader.questStars?.earned, 0);

    // Two sparkles land as room state on the session room (250 × 1.2 = 300),
    // and the panel stays mounted — this is the moment the count used to
    // freeze.
    awardGoals(session, ['g1', 'g2']);
    emitRoomSync();
    // The rate limiter lets the first tick straight through; a microtask hop
    // is all the stream needs to deliver it.
    await Future<void>.delayed(Duration.zero);

    expect(loader.missionProgress(missionId)?.xp, 300);
    expect(loader.missionProgress(missionId)?.satisfied, isTrue);
    expect(loader.questStars?.earned, 1);
  });

  test(
    'XP landing in the shared cache moves the meter without a sync',
    () async {
      stubOutline();
      registerCourseSpace();
      registerSession();
      MissionXpCache.instance.seed(xpByRoom: {sessionId: 100});

      final loader = QuestObjectivesLoader(client: client);
      addTearDown(loader.dispose);
      await loader.loadOutline(questId, courseRoomId: courseRoomId);
      expect(loader.missionProgress(missionId)?.xp, 100);

      MissionXpCache.instance.seed(xpByRoom: {sessionId: 320});
      // The cache notifies on a microtask (publishing mid-build is rejected).
      await Future<void>.delayed(Duration.zero);

      expect(loader.missionProgress(missionId)?.xp, 320);
      expect(loader.missionProgress(missionId)?.satisfied, isTrue);
    },
  );

  test('a sync before any outline has loaded publishes nothing — no course '
      'shows a denominator it has not resolved', () async {
    registerCourseSpace();
    final session = registerSession();
    awardGoals(session, ['g1']);
    MissionXpCache.instance.seed(xpByRoom: {sessionId: 100});

    final loader = QuestObjectivesLoader(client: client);
    addTearDown(loader.dispose);

    emitRoomSync();
    await Future<void>.delayed(Duration.zero);

    expect(loader.hasResolvedProgress, isFalse);
    expect(loader.questStars, isNull);
  });

  /// #8938 — collapsing the course card swaps it for the context bar (and
  /// expanding swaps back). Each is its own widget with its own loader, so the
  /// incoming one used to start from an empty resolution and the progress bar
  /// blanked for the frames its re-resolve took — a visible flicker on every
  /// toggle. The resolution is shared and course-scoped, so the surface taking
  /// over already has the numbers the outgoing one resolved.
  test('a second loader for the same course shows its progress immediately — '
      'the card/bar swap never blanks the bar', () async {
    stubOutline();
    registerCourseSpace();
    registerSession();
    MissionXpCache.instance.seed(xpByRoom: {sessionId: 200});

    final open = QuestObjectivesLoader(client: client);
    await open.loadOutline(questId, courseRoomId: courseRoomId);
    expect(open.missionProgress(missionId)?.xp, 200);

    // The card's token drops and the bar mounts: a fresh loader for the same
    // course, its own outline read still in flight.
    final swapped = QuestObjectivesLoader(client: client);
    addTearDown(swapped.dispose);
    final loading = swapped.loadOutline(questId, courseRoomId: courseRoomId);

    expect(
      swapped.missionProgress(missionId)?.xp,
      200,
      reason: 'the incoming surface must not render the empty bar',
    );
    expect(swapped.hasResolvedProgress, isTrue);

    await loading;
    open.dispose();
    expect(swapped.missionProgress(missionId)?.xp, 200);
  });
}

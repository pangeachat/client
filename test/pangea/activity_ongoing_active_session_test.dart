import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'get_test_client.dart';

/// #8278 — the Chats-list tile shows a session's star row only where its world
/// map card does, in the ongoing-active state (world-map.instructions.md,
/// "Goal Progress"). A session still filling seats draws seat circles there
/// instead, so seats and stars never compete for the row.
///
/// Also covers the pair of numbers the tile feeds that row: they are read
/// straight from room state — the learner's own role for the total, its awarded
/// goals for the numerator — the same pair the map reads.
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const otherId = '@other:fakeServer.notExisting';
  const activityId = 'activity-123';
  const sessionId = '!session:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
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
  /// produces, so the learner's own role carries the whole total.
  ActivityPlanModel plan() => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: 'sport',
      mode: 'Roleplay',
      objective: 'meet a fan',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'es',
      numberOfParticipants: 2,
    ),
    title: 'Meet a Fan at the Stadium',
    learningObjective: 'meet a fan',
    instructions: 'i',
    vocab: const [],
    activityId: activityId,
    roles: {
      'r1': ActivityRole(
        id: 'r1',
        name: 'Fan',
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

  /// A session room carrying [roles] as seat assignments and [awarded] as the
  /// orchestrator's per-role awards.
  Room session({
    required Map<String, ActivityRoleModel> roles,
    Map<String, List<String>> awarded = const {},
  }) {
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
        content: ActivityRolesModel(roles).toJson(),
      ),
    );
    if (awarded.isNotEmpty) {
      room.setState(
        stateEvent(
          room,
          type: PangeaEventTypes.orchestratorAwardedGoals,
          content: OrchestratorAwardedGoals(awards: awarded).toJson(),
        ),
      );
    }
    return room;
  }

  ActivityRoleModel mine({DateTime? finishedAt, DateTime? archivedAt}) =>
      ActivityRoleModel(
        id: 'r1',
        userId: userId,
        role: 'Fan',
        finishedAt: finishedAt,
        archivedAt: archivedAt,
      );

  ActivityRoleModel theirs() =>
      ActivityRoleModel(id: 'r2', userId: otherId, role: 'Visitor');

  group('isOngoingActiveSession', () {
    test('is true once the learner holds a live seat and none are left', () {
      expect(
        session(roles: {'r1': mine(), 'r2': theirs()}).isOngoingActiveSession,
        isTrue,
      );
    });

    test('is false while a seat is still open — that is the seat-circle '
        'state, not the star state', () {
      // The map's own Waiting/Ongoing discriminator: a free seat is
      // ongoingPending, which draws its participant row rather than stars.
      final room = session(roles: {'r1': mine()});
      expect(room.numRemainingRoles, 1);
      expect(room.isOngoingActiveSession, isFalse);
    });

    test('is false once the learner has finished their own role', () {
      expect(
        session(
          roles: {
            'r1': mine(finishedAt: DateTime.utc(2026, 1, 2)),
            'r2': theirs(),
          },
        ).isOngoingActiveSession,
        isFalse,
      );
    });

    test('is false for an archived role', () {
      expect(
        session(
          roles: {
            'r1': mine(archivedAt: DateTime.utc(2026, 1, 2)),
            'r2': theirs(),
          },
        ).isOngoingActiveSession,
        isFalse,
      );
    });

    test('is false in a full session the learner holds no seat in', () {
      // Someone else's session: no seat of theirs means no stars of theirs.
      expect(
        session(
          roles: {
            'r1': ActivityRoleModel(id: 'r1', userId: otherId, role: 'Fan'),
            'r2': theirs(),
          },
        ).isOngoingActiveSession,
        isFalse,
      );
    });
  });

  group('the star pair the tile feeds the row', () {
    test('totals the learner OWN role goals, not every role in the plan', () {
      final room = session(roles: {'r1': mine(), 'r2': theirs()});
      expect(room.ownRole?.allGoals.length, 3);
    });

    test('counts only goals awarded to the learner own role', () {
      final room = session(
        roles: {'r1': mine(), 'r2': theirs()},
        awarded: {
          'r1': ['slug-1', 'slug-2'],
          // The other player's awards must not inflate the learner's row.
          'r2': ['slug-4', 'slug-5', 'slug-6'],
        },
      );
      expect(room.ownCompletedGoals.length, 2);
    });

    test('is 0 of 0 before any goal is awarded', () {
      final room = session(roles: {'r1': mine(), 'r2': theirs()});
      expect(room.ownCompletedGoals, isEmpty);
    });
  });
}

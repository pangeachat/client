import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// One v3 activity-session room, described once: the session-state tests, the
/// map large-card tests, and the Chats-tile tests all assert over the same
/// room shape, so they cannot drift apart on what a session looks like.

const testSessionUserId = '@test:fakeServer.notExisting';
const testSessionActivityId = 'activity-123';
const testSessionRoomId = '!session:fakeServer.notExisting';

Event activitySessionStateEvent(
  Room room, {
  required String type,
  required Map<String, dynamic> content,
  String stateKey = '',
}) => Event(
  type: type,
  content: content,
  stateKey: stateKey,
  senderId: testSessionUserId,
  eventId: '\$${type}_$stateKey',
  originServerTs: DateTime.utc(2026, 1, 1, 12),
  room: room,
);

ActivityRoleGoal _goal(int n) =>
    ActivityRoleGoal(id: 'g$n', goalSlug: 'slug-$n', description: 'goal $n');

/// Two roles of three goals each — the uniform-per-role shape generation
/// produces, so the learner's own role carries the whole total.
ActivityPlanModel twoRoleActivityPlan({
  String activityId = testSessionActivityId,
}) => ActivityPlanModel(
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
      goals: [_goal(1), _goal(2), _goal(3)],
    ),
    'r2': ActivityRole(
      id: 'r2',
      name: 'Visitor',
      goal: null,
      goals: [_goal(4), _goal(5), _goal(6)],
    ),
  },
);

/// A session room carrying the embedded [twoRoleActivityPlan], [roles] as seat
/// assignments, [awarded] as the orchestrator's per-role awards, and — when
/// [avatarUrl] is set — the activity's picture as the room avatar, which is
/// what `launchActivitySession` writes at launch.
Room activitySessionRoom(
  Client client, {
  String roomId = testSessionRoomId,
  String activityId = testSessionActivityId,
  Map<String, ActivityRoleModel> roles = const {},
  Map<String, List<String>> awarded = const {},
  Uri? avatarUrl,
}) {
  final room = Room(id: roomId, client: client, membership: Membership.join);
  room.setState(
    activitySessionStateEvent(
      room,
      type: EventTypes.RoomCreate,
      content: {'type': '${PangeaRoomTypes.activitySession}:$activityId'},
    ),
  );
  room.setState(
    activitySessionStateEvent(
      room,
      type: PangeaEventTypes.activityPlan,
      content: twoRoleActivityPlan(activityId: activityId).toJson(),
    ),
  );
  room.setState(
    activitySessionStateEvent(
      room,
      type: PangeaEventTypes.activityRole,
      content: ActivityRolesModel(roles).toJson(),
    ),
  );
  if (awarded.isNotEmpty) {
    room.setState(
      activitySessionStateEvent(
        room,
        type: PangeaEventTypes.orchestratorAwardedGoals,
        content: OrchestratorAwardedGoals(awards: awarded).toJson(),
      ),
    );
  }
  if (avatarUrl != null) {
    room.setState(
      activitySessionStateEvent(
        room,
        type: EventTypes.RoomAvatar,
        content: {'url': avatarUrl.toString()},
      ),
    );
  }
  return room;
}

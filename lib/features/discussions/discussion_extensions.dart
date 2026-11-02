import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_mode.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:collection/collection.dart';

/// The names a discussion travels under (#9647). A discussion is an activity
/// in the Discussion mode, stored course-only in one of the course's Missions.
abstract class DiscussionIds {
  /// The plan mode that marks an activity as a discussion.
  static const String mode = 'Discussion';

  /// The plan's one shared role; every student's seat is on it.
  static const String roleId = 'participant';

  /// A student's seat in `pangea.activity_roles`, and the key their question
  /// awards are stored under: keyed by student, since every student holds
  /// the same role (synapse-pangea-chat `discussion_room`).
  static String seatKey(String userId) => '$roleId:$userId';
}

bool isDiscussionMode(String? mode) =>
    ActivityMode.fromPlanMode(mode) == ActivityMode.discussion;

extension DiscussionPlanExtension on ActivityPlanModel {
  bool get isDiscussion => isDiscussionMode(req.mode);

  /// The discussion's questions in order, as goals: the goals of its one
  /// shared participant role.
  List<ActivityRoleGoal> get discussionGoals =>
      roles.values.firstOrNull?.allGoals ?? const <ActivityRoleGoal>[];

  /// The discussion's questions in order.
  List<String> get discussionQuestions => [
    for (final goal in discussionGoals) goal.description,
  ];

  /// The photo a discussion shows, and its room's avatar.
  /// Null until the photo has resolved, never the generic placeholder: a
  /// room avatar set from it would keep the placeholder for good.
  Uri? get discussionImageUrl {
    final hero = heroBlock?.displayUrl();
    return hero != null ? Uri.tryParse(hero) : ownImageURL;
  }
}

extension DiscussionCardExtension on QuestActivityCard {
  bool get isDiscussion => isDiscussionMode(mode);
}

extension DiscussionRoomExtension on Room {
  /// The discussion this room is a chat for: an activity session room whose
  /// plan is in the Discussion mode. Null for every other room, and until the
  /// plan has loaded; wrap readers in a [ListenableBuilder] on
  /// [ActivityPlanRepo] to rebuild when it arrives.
  String? get discussionActivityId =>
      activityMode == ActivityMode.discussion ? activityId : null;

  /// The plan of the discussion this room is for; null for every other room
  /// and until it has loaded.
  ActivityPlanModel? get discussionPlan =>
      discussionActivityId == null ? null : activityPlan;
}

/// The learner's own progress in one discussion room (#9647): the questions
/// they have answered, by index, and whether they have ended. Both live on
/// the learner's own seat: the orchestrator's awards, and the seat's
/// `finished_at`, which "I'm done" stamps as it does in a roleplay.
class DiscussionProgress {
  final Set<int> answered;
  final bool ended;

  const DiscussionProgress({this.answered = const {}, this.ended = false});

  /// The first question not yet answered, or null when every one is.
  int? currentOf(int questionCount) {
    for (var i = 0; i < questionCount; i++) {
      if (!answered.contains(i)) return i;
    }
    return null;
  }
}

extension DiscussionProgressRoomExtension on Room {
  DiscussionProgress get discussionProgress => DiscussionProgress(
    answered: _answeredDiscussionQuestions,
    ended: ownRoleState?.isFinished ?? false,
  );

  /// The questions the orchestrator has awarded the learner's own seat, by
  /// index. Empty until the plan has loaded.
  Set<int> get _answeredDiscussionQuestions {
    final userId = client.userID;
    final goals = discussionPlan?.discussionGoals;
    if (userId == null || goals == null) return const {};
    final seat = DiscussionIds.seatKey(userId);
    final awarded = orchestratorAwardedGoals;
    return {
      for (var i = 0; i < goals.length; i++)
        if (awarded.isGoalCompletedForRole(
          seat,
          goals[i].id,
          goalSlug: goals[i].goalSlug,
        ))
          i,
    };
  }
}

extension DiscussionClientExtension on Client {
  /// The learner's rooms for [activityId], where they hold a seat: normally
  /// one. A room a course admin was joined to on its creation, to observe it,
  /// is not one until they join it as a participant (their seat), so it opens
  /// the start page rather than a chat they cannot write in.
  List<Room> discussionRoomsFor(String activityId) => [
    for (final room in rooms)
      if (room.membership == Membership.join &&
          room.discussionActivityId == activityId &&
          room.ownRoleState != null)
        room,
  ];

  /// The learner's room for [activityId] while they are still in the
  /// discussion: joined, holding a seat, and not ended. What shows it as
  /// Joined and carries its unread bubble.
  Room? activeDiscussionRoomFor(String activityId) => discussionRoomsFor(
    activityId,
  ).where((room) => !(room.ownRoleState?.isFinished ?? false)).firstOrNull;

  /// Whether the learner has ended [activityId] ("I'm done") in their room
  /// for it: its card reads Answered.
  bool hasAnsweredDiscussion(String activityId) =>
      activeDiscussionRoomFor(activityId) == null &&
      discussionRoomsFor(activityId).isNotEmpty;
}

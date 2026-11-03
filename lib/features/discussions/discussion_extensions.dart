import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_mode.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';

/// A discussion's seats (#9647). Every student holds the plan's one shared
/// role, so a seat in `pangea.activity_roles`, and the question awards stored
/// under it, are keyed by student (synapse-pangea-chat `discussion_room`).
abstract class DiscussionIds {
  static const String _roleId = 'participant';

  static String seatKey(String userId) => '$_roleId:$userId';
}

extension DiscussionPlanExtension on ActivityPlanModel {
  bool get isDiscussion => activityMode == ActivityMode.discussion;

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

/// The learner's own progress in one discussion room (#9647), both on their
/// own seat: the questions the orchestrator has awarded it, and the seat's
/// `finished_at`, which "I'm done" stamps as it does in a roleplay.
class DiscussionProgress {
  /// The ids of the questions they have answered.
  final Set<String> answered;
  final bool ended;

  const DiscussionProgress({this.answered = const {}, this.ended = false});

  bool isAnswered(ActivityRoleGoal question) => answered.contains(question.id);
}

extension DiscussionProgressRoomExtension on Room {
  DiscussionProgress get discussionProgress => DiscussionProgress(
    answered: _answeredDiscussionQuestions,
    ended: ownRoleState?.isFinished ?? false,
  );

  /// Empty until the plan has loaded.
  Set<String> get _answeredDiscussionQuestions {
    final userId = client.userID;
    final goals = discussionPlan?.discussionGoals;
    if (userId == null || goals == null) return const {};
    final seat = DiscussionIds.seatKey(userId);
    final awarded = orchestratorAwardedGoals;
    return {
      for (final goal in goals)
        if (awarded.isGoalCompletedForRole(
          seat,
          goal.id,
          goalSlug: goal.goalSlug,
        ))
          goal.id,
    };
  }
}

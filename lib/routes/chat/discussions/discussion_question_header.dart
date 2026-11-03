import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/discussions/discussion_extensions.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_content.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_header.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_goal_header_overlay.dart';
import 'package:fluffychat/routes/chat/activity_sessions/goal_header_label.dart';
import 'package:fluffychat/routes/chat/activity_sessions/goal_header_session_xp.dart';
import 'package:fluffychat/routes/chat/activity_sessions/goal_progress_mixin.dart';

/// A discussion's goal header (#9647): the activity goal header with the
/// discussion's questions as its goals, so a learner who joins a long
/// conversation still sees what it is answering. Open, it lists every
/// question and offers "I'm done!" (or "Wait, I'm not done!" once ended).
///
/// The question in front is the first one the learner hasn't answered: the
/// bot asks each student their own next question, so the room has no single
/// current one.
class DiscussionQuestionHeader extends StatefulWidget {
  final Room room;

  const DiscussionQuestionHeader({super.key, required this.room});

  @override
  State<DiscussionQuestionHeader> createState() =>
      _DiscussionQuestionHeaderState();
}

class _DiscussionQuestionHeaderState extends State<DiscussionQuestionHeader>
    with GoalProgressMixin {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  Future<void> _setEnded(bool ended) async {
    final room = widget.room;
    setState(() => _expanded = false);
    try {
      await (ended ? room.finishActivity() : room.continueActivity());
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'roomId': room.id});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).oopsSomethingWentWrong)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    // The learner's answers and their ending are room state.
    return StreamBuilder(
      stream: room.client.onSync.stream,
      builder: (context, _) {
        final goals =
            room.discussionPlan?.discussionGoals ?? const <ActivityRoleGoal>[];
        final progress = room.discussionProgress;
        final current = firstIncompleteGoal(goals, progress.isAnswered);
        final allAnswered = goals.isNotEmpty && current == null;
        final active = progress.ended ? null : current;
        final goalXp = GoalHeaderSessionXp.shows(room) ? kGoalXp : null;
        final sessionXp = GoalHeaderSessionXp(room: room);
        return ActivityGoalHeaderOverlay(
          showDropdown: _expanded,
          isComplete: allAnswered,
          onDismiss: _toggle,
          collapsed: ActivityDropdownHeader(
            goals: goals,
            isGoalCompleted: progress.isAnswered,
            onToggle: _toggle,
            activeGoalId: active?.id,
            subtitle: active == null
                ? null
                : GoalHeaderLabel(active.description, maxLines: 4),
            goalXp: goalXp,
            sessionXp: sessionXp,
          ),
          expanded: ActivityDropdownContent(
            goals: goals,
            isGoalCompleted: progress.isAnswered,
            onToggle: _toggle,
            activeGoalId: active?.id,
            showEndForMe: !progress.ended,
            showWaitNotDone: progress.ended,
            hasCompletedOwnGoals: allAnswered,
            finishActivityForMe: () => _setEnded(true),
            continueActivity: () => _setEnded(false),
            goalXp: goalXp,
            sessionXp: sessionXp,
          ),
        );
      },
    );
  }
}

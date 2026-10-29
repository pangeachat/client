import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/discussions/discussion_extensions.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/embed_pointer_shield.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_content.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_header.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_goal_header_card.dart';
import 'package:fluffychat/routes/chat/activity_sessions/goal_header_label.dart';
import 'package:fluffychat/widgets/goal_question_mark.dart';

/// A discussion's goal header (#9647): the activity goal header with the
/// discussion's questions as its goals, drawn as question marks. Collapsed,
/// it shows the learner's XP from this chat, a mark per question, and the
/// question in front of them; open, every question with its mark, and "I'm
/// done!" (or "Wait, I'm not done!" once ended). So a learner who joins a
/// long conversation still sees what it is answering.
///
/// Prototype: the question in front is the first one the learner hasn't
/// answered; in the full version it is the bot's latest question.
class DiscussionQuestionHeader extends StatefulWidget {
  final Room room;

  const DiscussionQuestionHeader({super.key, required this.room});

  @override
  State<DiscussionQuestionHeader> createState() =>
      _DiscussionQuestionHeaderState();
}

class _DiscussionQuestionHeaderState extends State<DiscussionQuestionHeader> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Fetch the discussion's plan as the chat opens. A build-time `ensure`
    // declines while the app is still starting and nothing asks again until
    // the next sync; `lookup` waits for the app, and its result notifies the
    // repo, which rebuilds this header and the chat's top block.
    final activityId = widget.room.discussionActivityId;
    if (activityId != null) {
      ActivityPlanRepo.instance.lookup(activityId).catchError((e, s) {
        ErrorHandler.logError(e: e, s: s, data: {'roomId': widget.room.id});
        return ActivityPlanLookup(ActivityPlanLookupStatus.failed, null, e);
      });
    }
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  Future<void> _setEnded(bool ended) async {
    final room = widget.room;
    final progress = room.discussionProgress;
    setState(() => _expanded = false);
    try {
      await room.setDiscussionProgress(
        DiscussionProgress(answered: progress.answered, ended: ended),
      );
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'roomId': room.id});
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final activityId = room.discussionActivityId;
    if (activityId == null) return const SizedBox.shrink();
    // The learner's progress is room account data: it changes on sync.
    // The plan loads after the room opens: rebuild when it arrives too.
    return ListenableBuilder(
      listenable: ActivityPlanRepo.instance,
      builder: (context, _) => StreamBuilder(
        stream: room.client.onSync.stream,
        builder: (context, _) => _build(context, activityId),
      ),
    );
  }

  Widget _build(BuildContext context, String activityId) {
    final room = widget.room;
    final planQuestions = room.discussionPlan?.discussionQuestions ?? const [];
    // The room is named for its discussion, so a room opened before its plan
    // loaded still shows something.
    final questions = planQuestions.isNotEmpty ? planQuestions : [room.name];
    final goals = [
      for (var i = 0; i < questions.length; i++)
        ActivityRoleGoal(id: 'question_$i', description: questions[i]),
    ];
    final progress = room.discussionProgress;
    bool isCompleted(ActivityRoleGoal goal) =>
        progress.answered.contains(goals.indexOf(goal));
    final current = progress.currentOf(questions.length);
    final allAnswered = current == null;
    final activeId = progress.ended || current == null
        ? null
        : goals[current].id;
    final xp = _DiscussionXp(room: room);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: _expanded ? 0 : null,
      child: GoalMarkScope(
        style: GoalMarkStyle.question,
        child: Stack(
          children: [
            if (_expanded) ...[
              const Positioned.fill(child: EmbedPointerShield()),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  child: ColoredBox(color: Colors.black.withAlpha(100)),
                ),
              ),
            ],
            ActivityGoalHeaderCard(
              showDropdown: _expanded,
              isComplete: allAnswered,
              collapsed: ActivityDropdownHeader(
                goals: goals,
                isGoalCompleted: isCompleted,
                onToggle: _toggle,
                activeGoalId: activeId,
                subtitle: activeId == null
                    ? null
                    : GoalHeaderLabel(questions[current!], maxLines: 4),
                goalXp: kGoalXp,
                sessionXp: xp,
              ),
              expanded: ActivityDropdownContent(
                goals: goals,
                isGoalCompleted: isCompleted,
                onToggle: _toggle,
                activeGoalId: activeId,
                showEndForMe: !progress.ended,
                showWaitNotDone: progress.ended,
                hasCompletedOwnGoals: allAnswered,
                finishActivityForMe: () => _setEnded(true),
                continueActivity: () => _setEnded(false),
                goalXp: kGoalXp,
                sessionXp: xp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The learner's XP from this chat so far — their messages here plus the
/// goal XP of each question they answered — drawn like a session's XP in the
/// goal header. Rebuilds as XP lands.
class _DiscussionXp extends StatelessWidget {
  final Room room;

  const _DiscussionXp({required this.room});

  @override
  Widget build(BuildContext context) {
    // A chat opened straight from a link may be the first reader of XP.
    MissionXpCache.instance.ensureWired();
    return ListenableBuilder(
      listenable: MissionXpCache.instance,
      builder: (context, _) {
        final xp = room.client.sessionXp(
          room,
          MissionXpCache.instance.creditedXpByRoom,
        );
        final theme = Theme.of(context);
        final l10n = L10n.of(context);
        return Semantics(
          label: l10n.xpAmount(xp),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 3.0,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 14.0,
                  // Decorative: the number beside it says it.
                  color: theme.pangea.goldGraphic,
                ),
                Text(
                  l10n.xpAmount(xp),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

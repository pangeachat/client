import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/languages/context_language_switch_target.dart';
import 'package:fluffychat/features/languages/language_flag_chip.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/routes/chat/activity_sessions/goal_header_constants.dart';
import 'package:fluffychat/routes/chat/activity_sessions/goal_header_label.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';

/// The collapsed face of the goal header. Its top row — the goal diamonds (or a
/// no-goals [title]) with a down chevron on the right — is the only part that
/// toggles the menu open.
///
/// The star row lives here — not in the expanded list — so it is the persistent
/// fly-up target ([GoalStarAnimation]).
class ActivityDropdownHeader extends StatelessWidget {
  final List<ActivityRoleGoal> goals;
  final bool Function(ActivityRoleGoal) isGoalCompleted;
  final String? activeGoalId;
  final VoidCallback onToggle;

  /// Shown under the top row: the active goal's label, a gold "I'm done!"
  /// button, or nothing (all goals complete, read-only).
  final Widget? subtitle;

  /// No-goals fallback: replaces the goal diamonds with a centered title.
  final String? title;

  /// This session's target language. The left slot — opposite the chevron —
  /// carries it as a switch when it isn't what the learner is learning: the
  /// one offer to switch a running session has, since it has no Start or
  /// Join button to attach one to (activities.instructions.md). Left null
  /// (the plain reserved slot) everywhere [ActivityDropdownHeader] renders
  /// outside a live session.
  final LanguageModel? contentLanguage;

  /// What each earned goal paid, drawn small under its diamond
  /// ([GoalStatusWidget.goalXp]); null draws the diamonds alone.
  final int? goalXp;

  /// The session's XP so far, at the row's far left (#9559); null on the
  /// start and summary pages.
  final Widget? sessionXp;

  const ActivityDropdownHeader({
    super.key,
    required this.goals,
    required this.isGoalCompleted,
    required this.onToggle,
    this.activeGoalId,
    this.subtitle,
    this.title,
    this.contentLanguage,
    this.goalXp,
    this.sessionXp,
  });

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final sessionXp = this.sessionXp;
    final sideSlot = sessionXp == null
        ? GoalHeaderConstants.chevronSlot
        : GoalHeaderConstants.xpSlot;
    final Widget center = title != null
        ? GoalHeaderLabel(title)
        : LayoutBuilder(
            builder: (context, constraints) {
              // Shrink the gap between stars (down to nearly touching) to keep
              // them on one row; Wrap only stacks them when even that overflows.
              const starBox = GoalStatusWidget.diamondBox;
              const maxSpacing = 12.0;
              const minSpacing = 2.0;
              var spacing = maxSpacing;
              if (goals.length > 1) {
                final fit =
                    (constraints.maxWidth - 1 - goals.length * starBox) /
                    (goals.length - 1);
                spacing = fit.clamp(minSpacing, maxSpacing);
              }
              return Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: spacing,
                runSpacing: 4.0,
                children: goals
                    .map(
                      (g) => GoalStatusWidget(
                        goal: g,
                        complete: isGoalCompleted(g),
                        isActive: g.id == activeGoalId,
                        showLabel: false,
                        goalXp: goalXp,
                        starTarget:
                            ActivitySessionConstants.goalMenuStarTargetId(g.id),
                      ),
                    )
                    .toList(),
              );
            },
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Only this top row toggles the menu; InkWell gives it a hover/ripple.
        // Its padding is equal above and below so the highlight reads as a
        // symmetric band rather than stopping flush under the stars.
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: GoalHeaderConstants.topPadding(context),
            ),
            // The session's XP at the far left and the chevron at the far
            // right (#9559), each in a slot of the same width so the diamonds
            // stay centred; both line up with the diamonds rather than with
            // the "+100" line under them.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: sideSlot,
                  height: GoalStatusWidget.diamondBox,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4.0,
                        children: [
                          ContextLanguageSwitchTarget(
                            contentLanguage: contentLanguage,
                            builder: (context, canSwitch) => !canSwitch
                                ? const SizedBox.shrink()
                                : LanguageFlagChip(
                                    language: contentLanguage,
                                    langCode: contentLanguage!.langCode,
                                    width: GoalHeaderConstants.chevronSlot,
                                    height: 16.0,
                                    fontSize: 8.0,
                                    radius: 2.0,
                                    borderWidth: 1.0,
                                    alwaysShowCode: false,
                                    tintColor: Theme.of(
                                      context,
                                    ).pangea.warningGraphic,
                                  ),
                          ),
                          ?sessionXp,
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(child: Center(child: center)),
                SizedBox(
                  width: sideSlot,
                  height: GoalStatusWidget.diamondBox,
                  child: const Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Icon(Icons.expand_more),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (subtitle != null)
          // The top gap is small because the toggle row's own bottom padding
          // already separates the subtitle from the stars.
          Padding(
            padding: EdgeInsets.fromLTRB(
              16.0,
              10.0,
              16.0,
              GoalHeaderConstants.topPadding(context),
            ),
            child: subtitle,
          ),
      ],
    );
  }
}

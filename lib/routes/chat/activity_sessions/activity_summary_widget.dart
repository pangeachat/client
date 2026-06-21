// ignore_for_file: implementation_imports

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_carousel.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_participant_list.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_vocab_widget.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';

class ActivitySummary extends StatelessWidget {
  final ActivityPlanModel activity;
  final Room? room;
  final Room? course;
  final Map<String, ActivityRoleModel> assignedRoles;

  final bool showInstructions;
  final VoidCallback toggleInstructions;

  final Function(String)? onTapParticipant;
  final bool Function(String)? canSelectParticipant;
  final bool Function(String)? isParticipantSelected;
  final bool Function(String)? isParticipantShimmering;
  final double Function(ActivityRoleModel?)? getParticipantOpacity;
  final bool Function(String)? showStarsCard;
  final Set<String> Function(String)? completedGoalsForRole;

  /// Opacity applied to the participant/role cards (role-selection fade).
  final double roleCardOpacity;

  /// When false, the participant/role cards are hidden.
  final bool showRoleCards;

  /// When false, the description + vocab section is hidden.
  final bool showDescriptionSection;

  /// Goals of the currently-selected role, rendered in the goals dropdown at
  /// the top of the start page. Null on the in-chat render.
  final List<ActivityRoleGoal>? goals;
  final Set<String> completedGoalIds;
  final bool goalsStartCollapsed;

  final ValueNotifier<Set<String>>? usedVocab;

  final bool inChat;

  const ActivitySummary({
    super.key,
    required this.activity,
    required this.showInstructions,
    required this.toggleInstructions,
    required this.assignedRoles,
    this.usedVocab,
    this.onTapParticipant,
    this.canSelectParticipant,
    this.isParticipantSelected,
    this.isParticipantShimmering,
    this.getParticipantOpacity,
    this.showStarsCard,
    this.completedGoalsForRole,
    this.roleCardOpacity = 1.0,
    this.showRoleCards = true,
    this.showDescriptionSection = true,
    this.goals,
    this.completedGoalIds = const {},
    this.goalsStartCollapsed = false,
    this.room,
    this.course,
    this.inChat = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Deep-link autostart: a video card opens the plan with `?autoplay=<index>`.
    // Only the plan page (not the in-session render) honors it.
    final autoplayParam = GoRouterState.of(
      context,
    ).uri.queryParameters['autoplay'];
    final autoplayIndex = (inChat || autoplayParam == null)
        ? null
        : int.tryParse(autoplayParam);
    return Center(
      child: Container(
        padding: const EdgeInsets.all(12.0),
        constraints: const BoxConstraints(
          maxWidth: FluffyThemes.columnWidth * 1.5,
        ),
        child: Column(
          spacing: 4.0,
          children: [
            if (goals != null)
              ActivityGoalsDropdown(
                goals: goals,
                completedGoalIds: completedGoalIds,
                startCollapsed: goalsStartCollapsed,
              ),
            (!inChat ||
                    !AppConfig.useActivityImageAsChatBackground ||
                    activity.hasPlayableMedia)
                ? ActivityMediaCarousel(
                    media: activity.media,
                    fallbackImageUrl: activity.imageURL,
                    borderRadius: BorderRadius.circular(20),
                    autoplayIndex: autoplayIndex,
                  )
                : const SizedBox.shrink(),
            if (showRoleCards)
              Opacity(
                opacity: roleCardOpacity,
                child: ActivityParticipantList(
                  activity: activity,
                  room: room,
                  assignedRoles: assignedRoles,
                  course: course,
                  onTap: onTapParticipant,
                  canSelect: canSelectParticipant,
                  isSelected: isParticipantSelected,
                  isShimmering: isParticipantShimmering,
                  getOpacity: getParticipantOpacity,
                  showStarsCard: showStarsCard,
                  completedGoalsForRole: completedGoalsForRole,
                ),
              ),
            if (showDescriptionSection)
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withAlpha(180),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 16.0,
                  children: [
                    Text(
                      activity.description,
                      style: TextStyle(fontSize: AppConfig.messageFontSize),
                    ),
                    const Divider(height: 1),
                    ActivityVocabWidget(
                      key: ValueKey("activity-summary-${activity.activityId}"),
                      vocab: activity.vocab,
                      langCode: activity.req.targetLanguage,
                      targetId: "activity-summary-vocab",
                      activityLangCode: activity.req.targetLanguage,
                      usedVocab: usedVocab,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ActivityGoalsDropdown extends StatefulWidget {
  final List<ActivityRoleGoal>? goals;
  final Set<String> completedGoalIds;
  final bool startCollapsed;

  const ActivityGoalsDropdown({
    super.key,
    required this.goals,
    required this.completedGoalIds,
    this.startCollapsed = false,
  });

  @override
  State<ActivityGoalsDropdown> createState() => _ActivityGoalsDropdownState();
}

class _ActivityGoalsDropdownState extends State<ActivityGoalsDropdown> {
  bool _visible = false;
  bool _innerExpanded = true;
  List<ActivityRoleGoal>? _displayGoals;

  @override
  void initState() {
    super.initState();
    _displayGoals = widget.goals;
    _visible = widget.goals != null && widget.goals!.isNotEmpty;
    _innerExpanded = !widget.startCollapsed;
  }

  @override
  void didUpdateWidget(covariant ActivityGoalsDropdown old) {
    super.didUpdateWidget(old);
    if (old.goals != widget.goals) {
      final hasGoals = widget.goals != null && widget.goals!.isNotEmpty;
      if (hasGoals) {
        setState(() {
          _displayGoals = widget.goals;
          _visible = true;
          _innerExpanded = true;
        });
      } else {
        setState(() => _visible = false);
        Future.delayed(FluffyThemes.animationDuration, () {
          if (mounted) setState(() => _displayGoals = null);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = _displayGoals ?? [];
    final theme = Theme.of(context);
    final firstGoal = goals.isNotEmpty ? goals.first : null;
    final remainingGoals = goals.length > 1
        ? goals.skip(1).toList()
        : <ActivityRoleGoal>[];

    return ClipRect(
      child: AnimatedAlign(
        duration: FluffyThemes.animationDuration,
        curve: Curves.easeInOut,
        heightFactor: _visible ? 1.0 : 0.0,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (firstGoal != null)
              InkWell(
                onTap: remainingGoals.isNotEmpty
                    ? () => setState(() => _innerExpanded = !_innerExpanded)
                    : null,
                child: Container(
                  height: 55.0,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(top: BorderSide(color: theme.dividerColor)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GoalStatusWidget(
                          goal: firstGoal,
                          complete: widget.completedGoalIds.contains(
                            firstGoal.id,
                          ),
                        ),
                      ),
                      if (remainingGoals.isNotEmpty)
                        Icon(
                          _innerExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                    ],
                  ),
                ),
              ),
            if (remainingGoals.isNotEmpty)
              ClipRect(
                child: AnimatedAlign(
                  duration: FluffyThemes.animationDuration,
                  curve: Curves.easeInOut,
                  heightFactor: _innerExpanded ? 1.0 : 0.0,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onPanUpdate: (d) {
                      if (d.delta.dy < -2) {
                        setState(() => _innerExpanded = false);
                      }
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxHeight =
                            MediaQuery.of(context).size.height * 0.7;
                        return ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: maxHeight),
                          child: SingleChildScrollView(
                            child: Container(
                              width: double.infinity,
                              color: theme.colorScheme.surface,
                              padding: const EdgeInsets.fromLTRB(
                                12.0,
                                12.0,
                                12.0,
                                24.0,
                              ),
                              child: Column(
                                spacing: 16.0,
                                mainAxisSize: MainAxisSize.min,
                                children: remainingGoals
                                    .map(
                                      (g) => SizedBox(
                                        height: 55.0,
                                        child: GoalStatusWidget(
                                          goal: g,
                                          complete: widget.completedGoalIds
                                              .contains(g.id),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class InlineEllipsisText extends StatelessWidget {
  final String text;
  final int? maxLines;
  final TextStyle? style;
  final WidgetSpan trailing;
  final double trailingWidth;

  const InlineEllipsisText({
    super.key,
    required this.text,
    required this.trailing,
    required this.trailingWidth,
    this.maxLines,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    final span = TextSpan(text: text, style: effectiveStyle);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: span,
          maxLines: maxLines,
          textDirection: TextDirection.ltr,
          ellipsis: '…',
        );

        tp.layout(maxWidth: constraints.maxWidth);
        String truncated = text;
        if (tp.didExceedMaxLines && maxLines != null) {
          // Find cutoff point where text fits
          final pos = tp.getPositionForOffset(
            Offset(
              constraints.maxWidth - trailingWidth,
              tp.preferredLineHeight * maxLines!,
            ),
          );
          final endIndex = tp.getOffsetBefore(pos.offset) ?? text.length;
          truncated = '${text.substring(0, endIndex).trimRight()}…';
        }

        tp.dispose();
        return RichText(
          text: TextSpan(
            children: [
              TextSpan(text: truncated, style: effectiveStyle),
              trailing, // always visible
            ],
          ),
          maxLines: maxLines,
          overflow: TextOverflow.clip, // prevent extra wrapping
        );
      },
    );
  }
}

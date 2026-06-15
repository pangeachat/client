import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_orchestrator/goal_status_widget.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_chat/activity_participant_list.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_chat/activity_vocab_widget.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_bottom_content.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_button_widget.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_start_page.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_state_controller.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/common/widgets/url_image_widget.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

class ActivitySessionStartView extends StatelessWidget {
  final ActivitySessionStartState controller;
  final ActivitySessionStateController sessionController;

  const ActivitySessionStartView(
    this.controller, {
    super.key,
    required this.sessionController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder(
      stream: Matrix.of(context).client.onRoomState.stream
          .where((update) => update.roomId == controller.widget.roomId)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final activity = controller.activity;

        return Scaffold(
          appBar: AppBar(
            leadingWidth: 52.0,
            title: activity == null
                ? null
                : Center(
                    child: Text(
                      activity.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: !FluffyThemes.isColumnMode(context)
                          ? const TextStyle(fontSize: 16)
                          : null,
                    ),
                  ),
            leading: Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.flag_outlined),
                onPressed: controller.submitActivityFeedback,
              ),
            ],
          ),
          body: SafeArea(
            child: controller.loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : controller.error != null || activity == null
                ? Center(
                    child: ErrorIndicator(
                      message: L10n.of(context).activityNotFound,
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          controller: controller.scrollController,
                          child: Column(
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  SizedBox(
                                    height: 350.0,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) =>
                                          ImageByUrl(
                                            imageUrl: activity.imageURL,
                                            borderRadius: BorderRadius.zero,
                                            width: constraints.maxWidth,
                                            replacement: Container(
                                              width: constraints.maxWidth,
                                              height: 350.0,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    theme
                                                        .colorScheme
                                                        .primaryContainer,
                                                    theme.colorScheme.surface,
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    top: 300.0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            theme.colorScheme.surface.withAlpha(
                                              0,
                                            ),
                                            theme.colorScheme.surface,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (sessionController.showRoleCards)
                                    Positioned(
                                      top: 250.0,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 600.0,
                                          ),
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 16.0,
                                            ),
                                            child: Opacity(
                                              opacity: sessionController
                                                  .roleCardOpacity,
                                              child: ActivityParticipantList(
                                                activity: activity,
                                                room: controller.activityRoom,
                                                assignedRoles:
                                                    controller.assignedRoles,
                                                course: controller.courseParent,
                                                onTap: sessionController
                                                    .selectRole,
                                                canSelect: sessionController
                                                    .canSelectRole,
                                                isSelected: sessionController
                                                    .isRoleSelected,
                                                isShimmering: sessionController
                                                    .isRoleShimmering,
                                                showStarsCard: sessionController
                                                    .showStarsCard,
                                                completedGoalsForRole:
                                                    sessionController
                                                        .completedGoalIdsForRole,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: _ActivityGoalsDropdown(
                                      goals:
                                          sessionController.selectedRoleGoals,
                                      completedGoalIds: sessionController
                                          .selectedRoleCompletedGoalIds,
                                      startCollapsed:
                                          sessionController.goalsStartCollapsed,
                                    ),
                                  ),
                                ],
                              ),
                              if (sessionController.showDescriptionSection)
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 600.0,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16.0,
                                        50.0,
                                        16.0,
                                        0.0,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        spacing: 12.0,
                                        children: [
                                          Text(
                                            activity.description,
                                            style: theme.textTheme.bodyLarge,
                                          ),
                                          if (activity.vocab.isNotEmpty)
                                            ActivityVocabWidget(
                                              key: ValueKey(
                                                'activity-start-vocab-${activity.activityId}',
                                              ),
                                              vocab: activity.vocab,
                                              langCode:
                                                  activity.req.targetLanguage,
                                              targetId: 'activity-start-vocab',
                                              usedVocab: null,
                                              activityLangCode:
                                                  activity.req.targetLanguage,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 600.0,
                                ),
                                padding: const EdgeInsets.all(12.0),
                                child: ActivitySessionBottomContent(
                                  sessionController,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ActivitySessionButtons(
                        controller: controller,
                        sessionController: sessionController,
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _ActivityGoalsDropdown extends StatefulWidget {
  final List<ActivityRoleGoal>? goals;
  final Set<String> completedGoalIds;
  final bool startCollapsed;

  const _ActivityGoalsDropdown({
    required this.goals,
    required this.completedGoalIds,
    this.startCollapsed = false,
  });

  @override
  State<_ActivityGoalsDropdown> createState() => _ActivityGoalsDropdownState();
}

class _ActivityGoalsDropdownState extends State<_ActivityGoalsDropdown> {
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
  void didUpdateWidget(covariant _ActivityGoalsDropdown old) {
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
                                      (g) => GoalStatusWidget(
                                        goal: g,
                                        complete: widget.completedGoalIds
                                            .contains(g.id),
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

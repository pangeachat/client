import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_init_error_indicator.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/analytics_summary/learning_progress_indicators.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../../config/themes.dart';
import '../../../widgets/avatar.dart';

class ActivityArchive extends StatelessWidget {
  /// When hosted inside the world map's right-docked analytics panel, hide the
  /// cross-metric [LearningProgressIndicators] header (its tabs navigate to the
  /// old left-column section routes). See routing.instructions.md.
  final bool embedded;
  const ActivityArchive({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Matrix.of(
        context,
      ).analyticsDataService.updateDispatcher.activityAnalyticsStream.stream,
      builder: (context, _) {
        final analyticsService = Matrix.of(context).analyticsDataService;
        final Room? analyticsRoom = Matrix.of(
          context,
        ).client.ownAnalyticsRoomLocalByL2;
        final archive = analyticsRoom?.archivedActivities ?? [];
        final selectedRoomId = GoRouterState.of(
          context,
        ).pathParameters['roomid'];
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsetsGeometry.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!embedded)
                    const LearningProgressIndicators(
                      selected: ProgressIndicatorEnum.activities,
                    ),
                  Expanded(
                    child: analyticsService.hasInitError
                        ? AnalyticsInitErrorIndicator(
                            reinitialize: analyticsService.reinitialize,
                          )
                        : MaxWidthBody(
                            showBorder: false,
                            withScrolling: false,
                            child: ListView.builder(
                              key: const PageStorageKey<String>(
                                'activity-archive',
                              ),
                              physics: const ClampingScrollPhysics(),
                              itemCount: archive.length + 1,
                              itemBuilder: (BuildContext context, int i) {
                                if (i == 0) {
                                  return InstructionsInlineTooltip(
                                    instructionsEnum: archive.isEmpty
                                        ? InstructionsEnum.noSavedActivitiesYet
                                        : InstructionsEnum
                                              .activityAnalyticsList,
                                    padding: const EdgeInsets.all(8.0),
                                  );
                                }
                                i--;
                                return AnalyticsActivityItem(
                                  room: archive[i],
                                  selected: archive[i].id == selectedRoomId,
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AnalyticsActivityItem extends StatelessWidget {
  final Room room;
  final bool selected;
  const AnalyticsActivityItem({
    super.key,
    required this.room,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final activity = room.activityPlan;
    final title = activity?.title ?? '';
    final goals = room.ownRole?.allGoals;

    final cefrLevel = room.activitySummaryByL1?.summary?.participants
        .firstWhereOrNull((p) => p.participantId == room.client.userID)
        ?.cefrLevel;

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? theme.colorScheme.secondaryContainer : null,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        clipBehavior: Clip.hardEdge,
        child: ListTile(
          visualDensity: const VisualDensity(vertical: -0.5),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: HoverBuilder(
            builder: (context, hovered) => AnimatedScale(
              duration: FluffyThemes.animationDuration,
              curve: FluffyThemes.animationCurve,
              scale: hovered ? 1.1 : 1.0,
              child: ExcludeSemantics(
                child: Avatar(
                  borderRadius: BorderRadius.circular(4.0),
                  mxContent: room.avatar,
                  name: room.getLocalizedDisplayname(),
                ),
              ),
            ),
          ),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: goals != null
              ? ActivityStarRow(
                  total: goals.length,
                  earned:
                      room
                          .orchestratorAwardedGoals
                          .awards[room.ownRoleState?.id]
                          ?.length ??
                      0,
                  iconSize: 22.0,
                )
              : null,
          trailing: cefrLevel != null
              ? Semantics(
                  label: L10n.of(context).difficultyLabel(cefrLevel),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: ExcludeSemantics(
                      child: Text(
                        cefrLevel.toUpperCase(),
                        style: const TextStyle(fontSize: 14.0),
                      ),
                    ),
                  ),
                )
              : null,
          onTap: () {
            AnalyticsNavigationUtil.navigateToAnalytics(
              context: context,
              view: ProgressIndicatorEnum.activities,
              activityRoomId: room.id,
            );
          },
        ),
      ),
    );
  }
}

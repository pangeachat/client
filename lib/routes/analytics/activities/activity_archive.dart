import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_init_error_indicator.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/roving_focus_group.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../../config/themes.dart';
import '../../../widgets/avatar.dart';

class ActivityArchive extends StatelessWidget {
  final Widget closeButton;
  const ActivityArchive({super.key, required this.closeButton});

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
          appBar: AppBar(
            leading: Center(child: closeButton),
            title: Text(
              L10n.of(context).stars,
              style: FluffyThemes.isColumnMode(context)
                  ? Theme.of(context).textTheme.titleLarge
                  : Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
            ),
            centerTitle: false,
            titleSpacing: 0,
          ),
          body: Padding(
            padding: const EdgeInsetsGeometry.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!analyticsService.hasInitError)
                  MaxWidthBody(
                    showBorder: false,
                    withScrolling: false,
                    padding: .only(top: 48),
                    addVerticalPadding: false,
                    child: InstructionsInlineTooltip(
                      instructionsEnum: archive.isEmpty
                          ? InstructionsEnum.noSavedActivitiesYet
                          : InstructionsEnum.activityAnalyticsList,
                      padding: const EdgeInsets.all(8.0),
                    ),
                  ),
                Expanded(
                  child: analyticsService.hasInitError
                      ? AnalyticsInitErrorIndicator(
                          reinitialize: analyticsService.reinitialize,
                        )
                      : MaxWidthBody(
                          showBorder: false,
                          withScrolling: false,
                          padding: .fromLTRB(32, 0, 32, 48),
                          addVerticalPadding: false,
                          child: Semantics(
                            label: L10n.of(context).starListLabel,
                            container: true,
                            // One Tab stop for the session list, arrow keys
                            // inside; Tab lands on the open session (#8935).
                            child: RovingFocusGroup(
                              ids: [for (final room in archive) room.id],
                              selectedId: selectedRoomId,
                              child: ListView.builder(
                                key: const PageStorageKey<String>(
                                  'activity-archive',
                                ),
                                physics: const ClampingScrollPhysics(),
                                itemCount: archive.length,
                                itemBuilder: (BuildContext context, int i) {
                                  return AnalyticsActivityItem(
                                    room: archive[i],
                                    rovingId: archive[i].id,
                                    selected: archive[i].id == selectedRoomId,
                                  );
                                },
                              ),
                            ),
                          ),
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

class AnalyticsActivityItem extends StatelessWidget {
  final Room room;
  final bool selected;

  /// This row's id in the enclosing [RovingFocusGroup]: the session list is
  /// one Tab stop, with the arrow keys moving between rows (#8935). Null for
  /// a row outside a group.
  final String? rovingId;

  const AnalyticsActivityItem({
    super.key,
    required this.room,
    this.selected = false,
    this.rovingId,
  });

  @override
  Widget build(BuildContext context) {
    final rovingId = this.rovingId;
    final focusNode = rovingId == null
        ? null
        : RovingFocusGroup.nodeOf(context, rovingId);

    final activity = room.activityPlan;
    // A v3 session's plan is hydrated from CMS, so it can be null (still
    // loading, or gone from the backend) and can land with an empty title. The
    // room was named after the activity at creation, so fall back to the room
    // name rather than a blank row (#9033) — the same rung the start page's
    // archived session lands on (activities.instructions.md).
    final planTitle = activity?.title ?? '';
    final title = planTitle.isNotEmpty
        ? planTitle
        : room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final goals = room.ownRole?.allGoals;

    final userId = room.client.userID;
    final summaryModel = room.activitySummaryByL1;
    final summary = summaryModel?.summary;
    final cefrLevel = summary?.participants
        .firstWhereOrNull((p) => p.participantId == userId)
        ?.cefrLevel;

    // The level and the stats come and go together: a session with no
    // generated summary keeps its title and stars and shows neither, rather
    // than a half-filled row (activities.instructions.md, "The Stars list").
    final analytics = summaryModel?.analytics;
    final stats = summary == null || analytics == null || userId == null
        ? null
        : _ActivitySessionStats(
            xp: analytics.xpForUser(userId),
            vocab: analytics.uniqueConstructCountForUser(
              userId,
              ConstructTypeEnum.vocab,
            ),
            grammar: analytics.uniqueConstructCountForUser(
              userId,
              ConstructTypeEnum.morph,
            ),
            onSelectedFill: selected,
          );

    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: selected ? theme.colorScheme.secondaryContainer : null,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          clipBehavior: Clip.hardEdge,
          child: ListTile(
            focusNode: focusNode,
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
            isThreeLine: stats != null,
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: goals == null && stats == null
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2.0,
                    children: [
                      if (goals != null)
                        ActivityStarRow(
                          total: goals.length,
                          earned:
                              room
                                  .orchestratorAwardedGoals
                                  .awards[room.ownRoleState?.id]
                                  ?.length ??
                              0,
                          iconSize: 22.0,
                        ),
                      ?stats,
                    ],
                  ),
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
      ),
    );
  }
}

/// The learner's own numbers from a saved session: the XP they earned, and how
/// many distinct vocabulary and grammar items they used. All three come from
/// the summary saved with the session, so the row can never disagree with the
/// end-of-activity card (activities.instructions.md, "The Stars list").
class _ActivitySessionStats extends StatelessWidget {
  final int xp;
  final int vocab;
  final int grammar;

  /// Whether the row is drawn on the selected fill. The gold XP text falls
  /// below the 4.5:1 contrast floor there, so it takes the surface ink instead.
  final bool onSelectedFill;

  const _ActivitySessionStats({
    required this.xp,
    required this.vocab,
    required this.grammar,
    required this.onSelectedFill,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Wrap(
      spacing: 10.0,
      runSpacing: 2.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.xpAmount(xp),
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: onSelectedFill
                ? theme.colorScheme.onSurface
                : theme.pangea.gold,
          ),
        ),
        _ActivitySessionStat(
          icon: ProgressIndicatorEnum.wordsUsed.icon,
          count: vocab,
          label: l10n.vocabItemsUsed(vocab),
        ),
        _ActivitySessionStat(
          icon: ProgressIndicatorEnum.morphsUsed.icon,
          count: grammar,
          label: l10n.grammarItemsUsed(grammar),
        ),
      ],
    );
  }
}

/// One count on the stats line: the analytics bar's icon for that kind of
/// item, the number, and the spoken [label] the number alone can't carry.
class _ActivitySessionStat extends StatelessWidget {
  final IconData icon;
  final int count;
  final String label;

  const _ActivitySessionStat({
    required this.icon,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 3.0,
          children: [
            Icon(icon, size: 15.0, color: theme.colorScheme.onSurfaceVariant),
            Text(
              "$count",
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

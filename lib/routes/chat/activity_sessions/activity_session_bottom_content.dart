import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/room_summaries/activity_summary_status_enum.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/features/tutorials/tutorial_target.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/user_profile_builder.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/chat/activity_sessions/not_started_session_controller.dart';

class ActivitySessionBottomContent extends StatelessWidget {
  final ActivitySessionStateController controller;

  /// Tutorial target id for the open-sessions list, or null when this mount
  /// isn't the claimant ([TutorialTarget] — one claimant per id).
  final String? openSessionsTargetId;

  const ActivitySessionBottomContent(
    this.controller, {
    super.key,
    this.openSessionsTargetId,
  });

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;

    if (controller is NotStartedSessionController) {
      return _NotStartedSessionBottomContent(
        controller,
        openSessionsTargetId: openSessionsTargetId,
      );
    }

    return SizedBox();
  }
}

class _NotStartedSessionBottomContent extends StatelessWidget {
  final NotStartedSessionController controller;
  final String? openSessionsTargetId;

  const _NotStartedSessionBottomContent(
    this.controller, {
    required this.openSessionsTargetId,
  });

  @override
  Widget build(BuildContext context) {
    if (controller.subPage.visibleStatuses.isEmpty) {
      return const SizedBox.shrink();
    }

    // The session a course ping pointed at gets the bell badge, so a learner
    // choosing between several open sessions lands in the right one (#8319).
    final ping = CoursePingBadgeCache.instance.value;
    final pingedRoomId =
        ping != null &&
            ping.courseId == controller.widget.course?.id &&
            ping.activityId == controller.widget.activityId
        ? ping.sessionRoomId
        : null;

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: FluffyThemes.columnWidth * 1.5,
      ),
      child: Column(
        children: [
          ...controller.subPage.visibleStatuses.map((status) {
            // Completed is scoped per-viewer ([visibleCompletedSessions]); every
            // other status lists the whole course.
            final roomSummaries = status == ActivitySummaryStatus.completed
                ? controller.visibleCompletedSessions
                : controller.activityStatuses.getSessionsByStatus(status);

            if (roomSummaries.isEmpty) return const SizedBox.shrink();

            final section = _ActivitySummaryStatusSection(
              status: status,
              roomSummaries: roomSummaries,
              pingedRoomId: pingedRoomId,
              onTap: controller.joinActivityByRoomId,
            );

            // Only the joinable (notStarted) section is a tutorial target, and
            // only when it has tiles — the target existing at all is what tells
            // the trigger the join list is showing with content. Its mount is
            // reported upward: on mobile it happens only after the sheet's
            // expand animation, past every other re-ask signal.
            if (status != ActivitySummaryStatus.notStarted) return section;
            return TutorialTarget(
              targetId: openSessionsTargetId,
              onMounted: controller.widget.controller.onTutorialSurfaceChanged,
              child: section,
            );
          }),
        ],
      ),
    );
  }
}

class _ActivitySummaryStatusSection extends StatelessWidget {
  final ActivitySummaryStatus status;
  final Map<String, RoomSummaryResponse> roomSummaries;

  /// The session room a course ping pointed at, or null — its tile gets the
  /// bell badge.
  final String? pingedRoomId;

  final Function(String) onTap;

  const _ActivitySummaryStatusSection({
    required this.status,
    required this.roomSummaries,
    required this.pingedRoomId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsGeometry.symmetric(
        horizontal: 20.0,
        vertical: 16.0,
      ),
      child: Column(
        spacing: 12.0,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              status.label(L10n.of(context), roomSummaries.length),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...roomSummaries.entries.map((e) {
            return _ActivitySessionDetailsTile(
              roomSummary: e.value,
              pinged: e.key == pingedRoomId,
              onTap: () => onTap(e.key),
            );
          }),
        ],
      ),
    );
  }
}

class _ActivitySessionDetailsTile extends StatelessWidget {
  final RoomSummaryResponse roomSummary;

  /// This session is the one a course ping pointed at: badge its corner.
  final bool pinged;

  final VoidCallback onTap;

  const _ActivitySessionDetailsTile({
    required this.roomSummary,
    required this.pinged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activityRoles = roomSummary.activityRoles;
    final activitySummary = roomSummary.activitySummary;
    final textSummary = activitySummary?.summary?.summary;
    final analytics = activitySummary?.analytics;
    final participants = roomSummary.membershipSummary.keys;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            borderRadius: BorderRadius.all(
              Radius.circular(AppConfig.borderRadius),
            ),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.all(
                  Radius.circular(AppConfig.borderRadius),
                ),
              ),
              padding: EdgeInsets.all(12.0),
              child: Column(
                spacing: 24.0,
                children: [
                  if (activitySummary != null)
                    Row(
                      spacing: 12.0,
                      children: [
                        Expanded(
                          child: Column(
                            spacing: 8.0,
                            children: [
                              if (textSummary != null) Text(textSummary),
                              if (analytics != null)
                                Row(
                                  spacing: 8.0,
                                  children: [
                                    Container(
                                      height: 20.0,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          AppConfig.borderRadius,
                                        ),
                                        color:
                                            theme.colorScheme.primaryContainer,
                                      ),
                                      child: Row(
                                        spacing: 4.0,
                                        children: [
                                          Text(
                                            "XP",
                                            style: TextStyle(
                                              fontSize: 12.0,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            "${analytics.totalXP}",
                                            style: TextStyle(fontSize: 12.0),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      height: 20.0,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          AppConfig.borderRadius,
                                        ),
                                        color:
                                            theme.colorScheme.primaryContainer,
                                      ),
                                      child: Row(
                                        spacing: 4.0,
                                        children: [
                                          Icon(
                                            ConstructTypeEnum
                                                .vocab
                                                .indicator
                                                .icon,
                                            size: 14.0,
                                          ),
                                          Text(
                                            "${analytics.totalUniqueConstructCount(ConstructTypeEnum.vocab)}",
                                            style: TextStyle(fontSize: 12.0),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      height: 20.0,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          AppConfig.borderRadius,
                                        ),
                                        color:
                                            theme.colorScheme.primaryContainer,
                                      ),
                                      child: Row(
                                        spacing: 4.0,
                                        children: [
                                          Icon(
                                            ConstructTypeEnum
                                                .morph
                                                .indicator
                                                .icon,
                                            size: 14.0,
                                          ),
                                          Text(
                                            "${analytics.totalUniqueConstructCount(ConstructTypeEnum.morph)}",
                                            style: TextStyle(fontSize: 12.0),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.arrow_forward),
                          tooltip: L10n.of(context).details,
                          onPressed: onTap,
                        ),
                      ],
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          spacing: 16.0,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...participants.map((userId) {
                              final role = activityRoles?.role(userId);

                              final userSummary = activitySummary?.summary
                                  ?.userSummary(userId);

                              final superlative =
                                  userSummary?.superlatives.firstOrNull;

                              return ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: 90.0),
                                child: Opacity(
                                  opacity: role == null ? 0.5 : 1,
                                  child: Column(
                                    spacing: 6.0,
                                    children: [
                                      // Name and avatar both come from the user's
                                      // own profile: this tile lists sessions the
                                      // learner has NOT joined, so there is no
                                      // member state to resolve them from and the
                                      // course-member lookup this replaced left
                                      // everyone at their localpart with a default
                                      // avatar (#8192).
                                      UserProfileName(
                                        userId: userId,
                                        style: const TextStyle(fontSize: 12.0),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                      UserProfileAvatar(
                                        userId: userId,
                                        size: 60.0,
                                      ),
                                      if (userSummary != null)
                                        Text(
                                          userSummary.cefrLevel,
                                          style: const TextStyle(
                                            fontSize: 12.0,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      if (superlative != null)
                                        Text(
                                          superlative,
                                          style: const TextStyle(
                                            fontSize: 12.0,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      if (activitySummary == null) Icon(Icons.arrow_forward),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (pinged)
            const Positioned(top: -8.0, right: -8.0, child: CoursePingBadge()),
        ],
      ),
    );
  }
}

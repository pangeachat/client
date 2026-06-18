import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_state_controller.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/not_started_session_controller.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/room_summaries/activity_summary_status_enum.dart';
import 'package:fluffychat/pangea/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';

class ActivitySessionBottomContent extends StatelessWidget {
  final ActivitySessionStateController controller;
  const ActivitySessionBottomContent(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;

    if (controller is NotStartedSessionController) {
      return _NotStartedSessionBottomContent(controller);
    }

    return SizedBox();
  }
}

class _NotStartedSessionBottomContent extends StatelessWidget {
  final NotStartedSessionController controller;
  const _NotStartedSessionBottomContent(this.controller);

  @override
  Widget build(BuildContext context) {
    if (controller.subPage.visibleStatuses.isEmpty) {
      return const SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: FluffyThemes.columnWidth * 1.5,
      ),
      child: Column(
        children: [
          ...controller.subPage.visibleStatuses.map((status) {
            final roomSummaries = controller.activityStatuses
                .getSessionsByStatus(status);

            if (roomSummaries.isEmpty) return const SizedBox.shrink();

            return _ActivitySummaryStatusSection(
              status: status,
              roomSummaries: roomSummaries,
              course: controller.course,
              onTap: controller.joinActivityByRoomId,
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

  final Room course;
  final Function(String) onTap;

  const _ActivitySummaryStatusSection({
    required this.status,
    required this.roomSummaries,
    required this.course,
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
              course: course,
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
  final Room course;
  final VoidCallback onTap;

  const _ActivitySessionDetailsTile({
    required this.roomSummary,
    required this.course,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activityRoles = roomSummary.activityRoles;
    final activitySummary = roomSummary.activitySummary;
    final textSummary = activitySummary?.summary?.summary;
    final analytics = activitySummary?.analytics;
    final participants = roomSummary.membershipSummary.keys;
    final users = course.getParticipants();
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: InkWell(
        borderRadius: BorderRadius.all(Radius.circular(AppConfig.borderRadius)),
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
                                    color: theme.colorScheme.primaryContainer,
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
                                    color: theme.colorScheme.primaryContainer,
                                  ),
                                  child: Row(
                                    spacing: 4.0,
                                    children: [
                                      Icon(
                                        ConstructTypeEnum.vocab.indicator.icon,
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
                                    color: theme.colorScheme.primaryContainer,
                                  ),
                                  child: Row(
                                    spacing: 4.0,
                                    children: [
                                      Icon(
                                        ConstructTypeEnum.morph.indicator.icon,
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
                          final user = users.firstWhereOrNull(
                            (u) => u.id == userId,
                          );

                          final displayName =
                              user?.calcDisplayname() ??
                              userId.localpart ??
                              userId;

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
                                  Text(
                                    displayName,
                                    style: const TextStyle(fontSize: 12.0),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                  Avatar(
                                    mxContent: user?.avatarUrl,
                                    name: userId.localpart,
                                    size: 60.0,
                                    userId: userId,
                                  ),
                                  if (userSummary != null)
                                    Text(
                                      userSummary.cefrLevel,
                                      style: const TextStyle(fontSize: 12.0),
                                      textAlign: TextAlign.center,
                                    ),
                                  if (superlative != null)
                                    Text(
                                      superlative,
                                      style: const TextStyle(fontSize: 12.0),
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
    );
  }
}

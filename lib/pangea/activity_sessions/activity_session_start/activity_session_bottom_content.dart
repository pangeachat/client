import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_state_controller.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/not_started_session_controller.dart';
import 'package:fluffychat/pangea/course_chats/open_roles_indicator.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/room_summaries/activity_summary_status_enum.dart';
import 'package:fluffychat/pangea/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/widgets/member_actions_popup_menu_button.dart';

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
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: FluffyThemes.columnWidth * 1.5,
      ),
      child: Column(
        children: [
          ...ActivitySummaryStatus.values.map((status) {
            final roomSummaries = controller.activityStatuses
                .getSessionsByStatus(status);

            if (roomSummaries.isEmpty) {
              return const SizedBox.shrink();
            }

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
            return _ActivitySessionListTile(
              roomSummary: e.value,
              status: status,
              course: course,
              onTap: () => onTap(e.key),
            );
          }),
        ],
      ),
    );
  }
}

class _ActivitySessionListTile extends StatelessWidget {
  final RoomSummaryResponse roomSummary;
  final ActivitySummaryStatus status;

  final Room course;
  final VoidCallback onTap;

  const _ActivitySessionListTile({
    required this.roomSummary,
    required this.status,
    required this.course,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activityPlan = roomSummary.activityPlan;

    // If activity is completed, show all roles, even for users who have left the
    // room (like the bot). Otherwise, show only joined users with roles
    final activityRoles = status == ActivitySummaryStatus.completed
        ? (roomSummary.activityRoles?.roles ?? {})
        : roomSummary.joinedUsersWithRoles;

    return ListTile(
      title: OpenRolesIndicator(
        roles: (activityPlan?.roles.values ?? [])
            .sorted((a, b) => a.id.compareTo(b.id))
            .toList(),
        assignedRoles: activityRoles.values.toList(),
        size: 40.0,
        spacing: 8.0,
        space: course,
        onUserTap: (user, context) {
          showMemberActionsPopupMenu(context: context, user: user);
        },
      ),
      trailing: course.isRoomAdmin ? const Icon(Icons.arrow_forward) : null,
      onTap: status.canJoin(course.isRoomAdmin) ? onTap : null,
    );
  }
}

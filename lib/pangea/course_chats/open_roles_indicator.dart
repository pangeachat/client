import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/widgets/avatar.dart';

class OpenRolesIndicator extends StatelessWidget {
  final List<ActivityRole> roles;
  final List<ActivityRoleModel> assignedRoles;
  final Room? room;
  final Room? space;

  final double? spacing;
  final double? size;
  final Function(User, BuildContext)? onUserTap;

  const OpenRolesIndicator({
    super.key,
    required this.roles,
    required this.assignedRoles,
    this.room,
    this.space,
    this.spacing,
    this.size,
    this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    final roomParticipants = room?.getParticipants() ?? [];
    final spaceParticipants = space?.getParticipants() ?? [];

    return Row(
      spacing: spacing ?? 2.0,
      children: [
        ...roles.map((role) {
          final assigned = assignedRoles.firstWhereOrNull(
            (r) => r.id == role.id,
          );

          final user = assigned != null
              ? roomParticipants.firstWhereOrNull(
                      (p) => p.id == assigned.userId,
                    ) ??
                    spaceParticipants.firstWhereOrNull(
                      (p) => p.id == assigned.userId,
                    )
              : null;

          if (assigned != null) {
            return Builder(
              builder: (context) => Avatar(
                mxContent: user?.avatarUrl,
                name:
                    user?.calcDisplayname() ??
                    assigned.userId.localpart ??
                    assigned.userId,
                size: size ?? 16,
                userId: assigned.userId,
                onTap: onUserTap != null && user != null
                    ? () => onUserTap!(user, context)
                    : null,
              ),
            );
          }

          return CircleAvatar(
            radius: size != null ? size! / 2 : 8,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              Icons.question_mark,
              size: size != null ? (size! / 2) : 8,
            ),
          );
        }),
      ],
    );
  }
}

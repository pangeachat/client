import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/hover_builder.dart';

class ActivityParticipantIndicator extends StatelessWidget {
  final ActivityRoleModel? assignedRole;

  final VoidCallback? onTap;
  final bool selected;
  final double opacity;

  const ActivityParticipantIndicator({
    super.key,
    this.assignedRole,
    this.selected = false,
    this.onTap,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AbsorbPointer(
      absorbing: onTap == null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: HoverBuilder(
            builder: (context, hovered) {
              return Opacity(
                opacity: opacity,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4.0,
                    horizontal: 8.0,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8.0),
                    color: hovered || selected
                        ? theme.colorScheme.primaryContainer.withAlpha(
                            selected ? 100 : 50,
                          )
                        : Colors.transparent,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 30.0,
                        backgroundColor: theme.colorScheme.primaryContainer,
                      ),
                      Text(
                        assignedRole?.role ?? L10n.of(context).participant,
                        style: const TextStyle(
                          fontSize: 12.0,
                        ),
                      ),
                      Text(
                        assignedRole?.userId.localpart ??
                            L10n.of(context).openRoleLabel,
                        style: TextStyle(
                          fontSize: 12.0,
                          color: assignedRole
                                  ?.userId.localpart?.lightColorAvatar ??
                              assignedRole?.role?.lightColorAvatar,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';

class ActivityRoleTooltip extends StatelessWidget {
  final Room room;
  final ValueNotifier<bool> hide;

  const ActivityRoleTooltip({
    required this.room,
    required this.hide,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: hide,
      builder: (context, hide, _) {
        if (!room.showActivityChatUI || room.ownRole?.goal == null || hide) {
          return const SizedBox();
        }

        return InlineTooltip(
          message: room.ownRole!.goal!,
          isClosed: room.hasDismissedGoalTooltip,
          onClose: () async {
            await room.dismissGoalTooltip();
          },
          padding: EdgeInsets.only(
            left: 16.0,
            right: 16.0,
            top: FluffyThemes.isColumnMode(context) ? 16.0 : 8.0,
          ),
        );
      },
    );
  }
}

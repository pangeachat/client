import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';

class ActivityRoleTooltip extends StatelessWidget {
  final Choreographer choreographer;

  const ActivityRoleTooltip({
    required this.choreographer,
    super.key,
  });

  Room get room => choreographer.chatController.room;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: choreographer,
      builder: (context, _) {
        if (!room.showActivityChatUI ||
            room.ownRole?.goal == null ||
            choreographer.itController.open.value) {
          return const SizedBox();
        }

        return InlineTooltip(
          message: room.ownRole!.goal!,
          isClosed: room.hasDismissedGoalTooltip,
          onClose: () async {
            await room.dismissGoalTooltip();
          },
          padding: const EdgeInsets.only(
            left: 16.0,
            top: 16.0,
            right: 16.0,
          ),
        );
      },
    );
  }
}

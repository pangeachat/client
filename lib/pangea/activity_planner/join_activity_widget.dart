import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/activity_planner/activity_room_extension.dart';
import 'package:fluffychat/widgets/hover_builder.dart';

class JoinActivityWidget extends StatelessWidget {
  final ChatController controller;

  const JoinActivityWidget({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            spacing: 16.0,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                spacing: 16.0,
                mainAxisSize: MainAxisSize.min,
                children:
                    List.generate(controller.room.remainingRoles, (index) {
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: HoverBuilder(
                      builder: (context, hovered) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4.0,
                            horizontal: 8.0,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8.0),
                            color: hovered
                                ? theme.colorScheme.primaryContainer
                                    .withAlpha(50)
                                : Colors.transparent,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 30.0,
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                              ),
                              Text(
                                L10n.of(context).participant,
                                style: const TextStyle(
                                  fontSize: 12.0,
                                ),
                              ),
                              Text(
                                "OPEN",
                                style: TextStyle(
                                  fontSize: 12.0,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                }),
              ),
              Text(
                L10n.of(context).unjoinedActivityMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isColumnMode ? 18.0 : 14.0,
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16.0),
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  backgroundColor: theme.colorScheme.primaryContainer,
                ),
                onPressed: () {
                  controller.room.setActivityRole(
                    controller.room.client.userID!,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(L10n.of(context).confirmRole),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

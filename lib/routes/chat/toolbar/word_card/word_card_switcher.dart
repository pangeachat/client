import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/routes/chat/toolbar/layout/message_selection_positioner.dart';
import 'package:fluffychat/routes/chat/toolbar/reading_assistance/select_mode_buttons.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/reading_assistance_content.dart';

class WordCardSwitcher extends StatelessWidget {
  final MessageSelectionPositionerState controller;
  const WordCardSwitcher({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.widget.overlayController.selectedMode,
      builder: (context, mode, _) {
        return AnimatedSize(
          alignment: controller.ownMessage
              ? Alignment.bottomRight
              : Alignment.bottomLeft,
          duration: FluffyThemes.animationDuration,
          child: controller.widget.overlayController.selectedToken != null
              ? ReadingAssistanceContent(
                  overlayController: controller.widget.overlayController,
                )
              : mode != SelectMode.emoji &&
                    !controller.pangeaMessageEvent.room.isActivityFinished
              ? ValueListenableBuilder(
                  valueListenable: controller.reactionNotifier,
                  builder: (context, _, _) => MessageReactionPicker(
                    chatController: controller.widget.chatController,
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }
}

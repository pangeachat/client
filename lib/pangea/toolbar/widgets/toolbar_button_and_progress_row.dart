import 'dart:math';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_meaning_button.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class ToolbarButtonAndProgressRow extends StatelessWidget {
  final Event event;
  final MessageOverlayController overlayController;
  final bool shouldShowToolbarButtons;

  const ToolbarButtonAndProgressRow({
    required this.event,
    required this.overlayController,
    required this.shouldShowToolbarButtons,
    super.key,
  });

  double? get proportionOfActivitiesCompleted =>
      overlayController.pangeaMessageEvent?.proportionOfActivitiesCompleted;

  static const double iconWidth = 36.0;
  static const double buttonSize = 40.0;

  @override
  Widget build(BuildContext context) {
    if (event.messageType == MessageTypes.Audio || !shouldShowToolbarButtons) {
      return const SizedBox();
    }

    if (!overlayController.showToolbarButtons) {
      return const SizedBox();
    }

    return Container(
      height: AppConfig.toolbarButtonAndProgressColumnHeight,
      width: AppConfig.toolbarButtonsColumnWidth,
      decoration: BoxDecoration(
        color: MessageModeExtension.barAndLockedButtonColor(context),
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      ),
      // margin: const EdgeInsets.symmetric(horizontal: iconWidth / 2),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Stack(
            children: [
              AnimatedContainer(
                duration: FluffyThemes.animationDuration,
                width: AppConfig.toolbarButtonsColumnWidth,
                height: overlayController.isPracticeComplete
                    ? AppConfig.toolbarButtonAndProgressColumnHeight
                    : min(
                        AppConfig.toolbarButtonAndProgressColumnHeight,
                        AppConfig.toolbarButtonAndProgressColumnHeight *
                            proportionOfActivitiesCompleted!,
                      ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                  color: AppConfig.success,
                ),
                margin: const EdgeInsets.symmetric(horizontal: iconWidth / 2),
              ),
            ],
          ),
          Column(
            children: [
              MessageMeaningButton(
                buttonSize: buttonSize,
                overlayController: overlayController,
              ),
              SizedBox(
                height: MessageMode.messageTextToSpeech.pointOnBar *
                        AppConfig.toolbarButtonAndProgressColumnHeight -
                    buttonSize,
              ),
              ToolbarButton(
                mode: MessageMode.messageTextToSpeech,
                overlayController: overlayController,
                buttonSize: buttonSize,
              ),
              SizedBox(
                height: MessageMode.messageTranslation.pointOnBar *
                        AppConfig.toolbarButtonAndProgressColumnHeight -
                    MessageMode.messageTextToSpeech.pointOnBar *
                        AppConfig.toolbarButtonAndProgressColumnHeight -
                    buttonSize -
                    buttonSize,
              ),
              ToolbarButton(
                mode: MessageMode.messageTranslation,
                overlayController: overlayController,
                buttonSize: buttonSize,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

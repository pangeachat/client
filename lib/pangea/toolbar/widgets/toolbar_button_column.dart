import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class ToolbarButtonRow extends StatelessWidget {
  final MessageOverlayController overlayController;
  final bool shouldShowToolbarButtons;

  const ToolbarButtonRow({
    required this.overlayController,
    required this.shouldShowToolbarButtons,
    super.key,
  });

  static const double iconWidth = 36.0;
  static const double buttonSize = 40.0;
  static const barMargin =
      EdgeInsets.symmetric(horizontal: iconWidth / 2, vertical: buttonSize / 2);

  @override
  Widget build(BuildContext context) {
    if (overlayController.event.messageType == MessageTypes.Audio ||
        !shouldShowToolbarButtons ||
        !(overlayController.pangeaMessageEvent?.messageDisplayLangIsL2 ??
            false)) {
      return const SizedBox(
        height: AppConfig.toolbarButtonsHeight,
      );
    }

    return SizedBox(
      height: AppConfig.toolbarButtonsHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              ToolbarButton(
                mode: MessageMode.messageTranslation,
                overlayController: overlayController,
                onPressed: overlayController.updateToolbarMode,
                buttonSize: buttonSize,
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            spacing: 4.0,
            children: [
              Container(
                width: buttonSize + 4,
                height: buttonSize + 4,
                alignment: Alignment.center,
                child: ToolbarButton(
                  mode: MessageMode.wordMorph,
                  overlayController: overlayController,
                  onPressed: overlayController.updateToolbarMode,
                  buttonSize: buttonSize,
                ),
              ),
              Container(
                width: buttonSize + 4,
                height: buttonSize + 4,
                alignment: Alignment.center,
                child: ToolbarButton(
                  mode: MessageMode.wordMeaning,
                  overlayController: overlayController,
                  onPressed: overlayController.updateToolbarMode,
                  buttonSize: buttonSize,
                ),
              ),
              Container(
                width: buttonSize + 4,
                height: buttonSize + 4,
                alignment: Alignment.center,
                child: ToolbarButton(
                  mode: MessageMode.listening,
                  overlayController: overlayController,
                  onPressed: overlayController.updateToolbarMode,
                  buttonSize: buttonSize,
                ),
              ),
              Container(
                width: buttonSize + 4,
                height: buttonSize + 4,
                alignment: Alignment.center,
                child: ToolbarButton(
                  mode: MessageMode.wordEmoji,
                  overlayController: overlayController,
                  onPressed: overlayController.updateToolbarMode,
                  buttonSize: buttonSize,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class ToolbarButtonColumn extends StatelessWidget {
  final Event event;
  final MessageOverlayController overlayController;
  final bool shouldShowToolbarButtons;
  final double height;
  final double width;

  const ToolbarButtonColumn({
    required this.event,
    required this.overlayController,
    required this.shouldShowToolbarButtons,
    required this.height,
    required this.width,
    super.key,
  });

  static const double iconWidth = 36.0;
  static const double buttonSize = 40.0;
  static const barMargin =
      EdgeInsets.symmetric(horizontal: iconWidth / 2, vertical: buttonSize / 2);

  @override
  Widget build(BuildContext context) {
    if (event.messageType == MessageTypes.Audio ||
        !shouldShowToolbarButtons ||
        !(overlayController.pangeaMessageEvent?.messageDisplayLangIsL2 ??
            false)) {
      return SizedBox(height: height, width: width);
    }

    return Container(
      height: height,
      width: width,
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 4.0,
        children: [
          ToolbarButton(
            mode: MessageMode.wordMorph,
            overlayController: overlayController,
            onPressed: overlayController.updateToolbarMode,
            buttonSize: buttonSize,
          ),
          ToolbarButton(
            mode: MessageMode.wordMeaning,
            overlayController: overlayController,
            onPressed: overlayController.updateToolbarMode,
            buttonSize: buttonSize,
          ),
          ToolbarButton(
            mode: MessageMode.messageTextToSpeech,
            overlayController: overlayController,
            onPressed: overlayController.updateToolbarMode,
            buttonSize: buttonSize,
          ),
          ToolbarButton(
            mode: MessageMode.wordEmoji,
            overlayController: overlayController,
            onPressed: overlayController.updateToolbarMode,
            buttonSize: buttonSize,
          ),
        ],
      ),
    );
  }
}

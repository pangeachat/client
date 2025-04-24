import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';

class SelectModeButtons extends StatelessWidget {
  final MessageOverlayController overlayController;

  const SelectModeButtons({
    required this.overlayController,
    super.key,
  });

  static const double iconWidth = 36.0;
  static const double buttonSize = 40.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppConfig.toolbarButtonsHeight,
      alignment: Alignment.bottomCenter,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        spacing: 4.0,
        children: [
          Tooltip(
            message: "Audio",
            child: PressableButton(
              borderRadius: BorderRadius.circular(20),
              color: Theme.of(context).colorScheme.primaryContainer,
              onPressed: () {},
              playSound: true,
              child: Container(
                height: buttonSize,
                width: buttonSize,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.volume_up,
                  size: 20,
                  // color: mode == overlayController.toolbarMode
                  //     ? Colors.white
                  //     : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

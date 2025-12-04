import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_practice_mode_enum.dart';

class ToolbarButton extends StatelessWidget {
  final MessagePracticeMode mode;
  final VoidCallback setMode;

  final bool isComplete;
  final bool isSelected;

  const ToolbarButton({
    required this.mode,
    required this.setMode,
    required this.isComplete,
    required this.isSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final color = mode.iconButtonColor(context, isComplete);
    return Container(
      width: 44.0,
      height: 44.0,
      alignment: Alignment.center,
      child: Tooltip(
        message: mode.tooltip(context),
        child: PressableButton(
          borderRadius: BorderRadius.circular(20),
          depressed: isSelected,
          color: color,
          onPressed: setMode,
          playSound: true,
          colorFactor:
              Theme.of(context).brightness == Brightness.light ? 0.55 : 0.3,
          child: Container(
            height: 40.0,
            width: 40.0,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(
              mode.icon,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

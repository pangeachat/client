import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/message_practice_mode_enum.dart';

class ToolbarButton extends StatelessWidget {
  final MessagePracticeMode mode;
  final VoidCallback setMode;

  final bool isComplete;
  final bool isSelected;
  final bool shimmer;

  const ToolbarButton({
    required this.mode,
    required this.setMode,
    required this.isComplete,
    required this.isSelected,
    this.shimmer = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = mode.iconButtonColor(context, isComplete);
    final ink = mode.iconButtonInk(context, isComplete);
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
          colorFactor: theme.brightness == Brightness.light ? 0.55 : 0.3,
          builder: (context, depressed, shadowColor) => ShimmerBackground(
            enabled: shimmer,
            child: Container(
              height: 40.0,
              width: 40.0,
              decoration: BoxDecoration(
                color: depressed ? shadowColor : color,
                shape: BoxShape.circle,
              ),
              child: Icon(
                mode.icon,
                size: 20,
                // The pressed fill is the rest fill darkened, so its own ink
                // can stop reading on it; the theme's light tone always does.
                color: depressed ? theme.lightTone : ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

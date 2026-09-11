import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';

class HintButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool depressed;
  final IconData icon;

  const HintButton({
    required this.onPressed,
    required this.depressed,
    super.key,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressableButton(
      borderRadius: BorderRadius.circular(20),
      color: theme.colorScheme.primaryContainer,
      onPressed: onPressed,
      depressed: depressed,
      playSound: true,
      colorFactor: 0.3,
      builder: (context, depressed, shadowColor) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 40.0,
            width: 40.0,
            decoration: BoxDecoration(
              color: depressed
                  ? shadowColor
                  : theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
          ),
          Icon(
            icon,
            size: 20,
            // A darkened fill loses its own ink; the theme's light tone reads.
            color: depressed
                ? theme.lightTone
                : theme.colorScheme.onPrimaryContainer,
          ),
        ],
      ),
    );
  }
}

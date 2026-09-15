import 'package:flutter/material.dart';

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
      color: theme.colorScheme.primary,
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
              color: depressed ? shadowColor : theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          Icon(
            icon,
            size: 20,
            // onPrimary reads on the fill and on its pressed, darkened cut.
            color: theme.colorScheme.onPrimary,
          ),
        ],
      ),
    );
  }
}

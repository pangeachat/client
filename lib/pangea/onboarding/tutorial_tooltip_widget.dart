import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';

class TutorialTooltipWidget extends StatelessWidget {
  final String text;

  const TutorialTooltipWidget({required this.text, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        spacing: 8.0,
        children: [
          BotFace(width: 32.0, expression: BotExpression.gold),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.surface,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

class TutorialOverlayMessage extends StatelessWidget {
  final String message;

  const TutorialOverlayMessage(
    this.message, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          // color: Theme.of(context).colorScheme.onSurface,
          color: Color.alphaBlend(
            Theme.of(context).colorScheme.surface.withAlpha(70),
            AppConfig.gold,
          ),
          borderRadius: BorderRadius.circular(12.0),
        ),
        alignment: Alignment.center,
        child: Row(
          spacing: 4.0,
          children: [
            Icon(
              Icons.lightbulb,
              size: 20.0,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            Flexible(
              child: Text(
                message,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

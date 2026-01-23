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
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          // color: Theme.of(context).colorScheme.onSurface,
          color: Color.alphaBlend(
            Theme.of(context).colorScheme.surface.withAlpha(70),
            AppConfig.gold,
          ),
          borderRadius: BorderRadius.circular(12.0),
        ),
        width: 350,
        alignment: Alignment.center,
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(
                  Icons.info_outlined,
                  size: 20.0,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const WidgetSpan(child: SizedBox(width: 4.0)),
              TextSpan(
                text: message,
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

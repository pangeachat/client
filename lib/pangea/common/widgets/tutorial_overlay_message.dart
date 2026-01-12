import 'package:flutter/material.dart';

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
          color: Theme.of(context).colorScheme.onSurface,
          borderRadius: BorderRadius.circular(12.0),
        ),
        width: 200,
        alignment: Alignment.center,
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              color: Theme.of(context).colorScheme.surface,
            ),
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(
                  Icons.info_outlined,
                  size: 16.0,
                  color: Theme.of(context).colorScheme.surface,
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

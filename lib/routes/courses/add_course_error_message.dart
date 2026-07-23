import 'package:flutter/material.dart';

import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/widgets/avatar.dart';

class AddCourseErrorMessage extends StatelessWidget {
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  const AddCourseErrorMessage({
    super.key,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12.0,
          children: [
            const BotFace(
              expression: BotExpression.addled,
              width: Avatar.defaultSize * 1.5,
            ),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: onPressed,
                label: Text(buttonLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 14.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

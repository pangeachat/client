import 'package:flutter/material.dart';

import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/dialog_wrapper.dart';

class FeedbackResponseDialog extends StatelessWidget {
  final String title;
  final String feedback;
  final String? description;

  const FeedbackResponseDialog({
    super.key,
    required this.title,
    required this.feedback,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return DialogWrapper(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      maxHeight: 325.0,
      padding: const EdgeInsets.all(12.0),
      child: SingleChildScrollView(
        child: Column(
          spacing: 20.0,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: L10n.of(context).close,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(
                  width: 40.0,
                  height: 40.0,
                  child: Center(child: Icon(Icons.flag_outlined)),
                ),
              ],
            ),
            Column(
              spacing: 20.0,
              mainAxisSize: MainAxisSize.min,
              children: [
                const BotFace(width: 60.0, expression: BotExpression.idle),
                Text(feedback, textAlign: TextAlign.center),
                if (description != null)
                  Text(description!, textAlign: TextAlign.center),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

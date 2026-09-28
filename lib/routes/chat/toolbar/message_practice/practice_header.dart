import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/message_practice_mode_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/toolbar_button.dart';

/// The practice surface's own chrome, above the message: the four modes, how
/// far the current one has got, and the way out. Practice used to be left only
/// by tapping the backdrop, which shows nothing (#6259).
class PracticeHeader extends StatelessWidget {
  final PracticeController controller;
  final VoidCallback onClose;

  const PracticeHeader(this.controller, {required this.onClose, super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final practiceMode = controller.practiceMode;
        final totalSteps = controller.totalSteps;

        // A Wrap, not a Row: four mode buttons, the step count and the close
        // control overflow a narrow window once the device text size is
        // turned up.
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4.0,
          children: [
            ...MessagePracticeMode.practiceModes.map((mode) {
              final complete = controller.isPracticeSessionDone(
                mode.associatedActivityType!,
              );
              return ToolbarButton(
                mode: mode,
                setMode: () => controller.updateToolbarMode(mode),
                isComplete: complete,
                isSelected: practiceMode == mode,
                shimmer:
                    practiceMode == MessagePracticeMode.noneSelected &&
                    !complete,
              );
            }),
            if (totalSteps > 0)
              Text(
                L10n.of(
                  context,
                ).practiceStepProgress(controller.completedSteps, totalSteps),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: L10n.of(context).closePractice,
              onPressed: onClose,
            ),
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

/// What a learner chose when ending an activity with goals left
/// (activity-session.instructions.md, "The goal header").
enum EndActivityChoice {
  /// They say they finished every goal: end, and tell the team which goals
  /// the orchestrator did not mark.
  finishedAllGoals,

  /// End as they are.
  justEnd,
}

/// Asks before "I'm done!" ends a role whose goals are not all marked done.
/// Null when the learner cancels or dismisses it.
Future<EndActivityChoice?> showEndActivityDialog(BuildContext context) =>
    showAdaptiveDialog<EndActivityChoice>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (context) {
        final l10n = L10n.of(context);
        return AlertDialog.adaptive(
          title: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 256),
            child: Text(l10n.endActivityGoalsLeftTitle),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 256),
            child: Text(l10n.endActivityGoalsLeftMessage),
          ),
          actions: [
            AdaptiveDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            AdaptiveDialogAction(
              onPressed: () =>
                  Navigator.of(context).pop(EndActivityChoice.justEnd),
              child: Text(l10n.endActivityJustEnd),
            ),
            AdaptiveDialogAction(
              onPressed: () =>
                  Navigator.of(context).pop(EndActivityChoice.finishedAllGoals),
              autofocus: true,
              child: Text(l10n.endActivityFinishedAllGoals),
            ),
          ],
        );
      },
    );

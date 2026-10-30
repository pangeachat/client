import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_chat_controller.dart';

/// Bottom status bar for a session the user has finished while others are
/// still going: the waiting state, with a way back in. The learner's own card
/// shows in the chat meanwhile, with its own loading and error states
/// (`ActivitySummaryCards`), so the bar stays collapsed and the rating card
/// above it doesn't get pushed around (#8018). Saving is automatic
/// (ActivityAutoSaveService) — there is no manual save step here.
class ActivityFinishedStatusMessage extends StatelessWidget {
  final ActivityChatController activityController;

  const ActivityFinishedStatusMessage({
    super.key,
    required this.activityController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = activityController.room;

    // The summary view recomputes on every role and membership change, so the
    // bar follows the room as learners finish or leave.
    return ValueListenableBuilder(
      valueListenable: activityController.summaryView,
      builder: (context, _, _) => AnimatedSize(
        alignment: Alignment.bottomCenter,
        duration: FluffyThemes.animationDuration,
        child: room.hasCompletedRole && !room.isActivityFinished
            ? Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(top: BorderSide(color: theme.dividerColor)),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _WaitSection(onContinue: room.continueActivity),
                  ),
                ),
              )
            : const SizedBox(),
      ),
    );
  }
}

class _WaitSection extends StatelessWidget {
  final VoidCallback onContinue;

  const _WaitSection({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      spacing: 12,
      children: [
        Text(
          L10n.of(context).waitingForOthersToFinish,
          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
        ElevatedButton(
          onPressed: onContinue,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            foregroundColor: theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surface,
            side: BorderSide(
              color: theme.brightness == Brightness.light
                  ? theme.colorScheme.primary.withAlpha(120)
                  : theme.colorScheme.primaryContainer,
            ),
          ),
          child: Text(
            L10n.of(context).waitNotDone,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

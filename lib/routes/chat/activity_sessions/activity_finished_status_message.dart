import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Bottom status bar for a session the user has finished: shows the waiting
/// state while others are still going, then the summary's error states.
/// Generation itself loads in the chat, not here ([ActivityUserSummaries]).
/// Saving is automatic (ActivityAutoSaveService) — there is no manual save
/// step here.
class ActivityFinishedStatusMessage extends StatelessWidget {
  final ChatController controller;

  const ActivityFinishedStatusMessage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!controller.room.hasCompletedRole) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    final finished = controller.room.isActivityFinished;

    final showsSummaries = MatrixState
        .pangeaController
        .subscriptionController
        .showSubscriptionGatedContent;

    return ValueListenableBuilder(
      valueListenable: controller.activityController.summaryView,
      builder: (context, view, _) {
        // A summary still generating renders in the chat instead, so the bar
        // stays collapsed and the rating card above it doesn't get pushed
        // around (#8018). An unsubscribed learner gets no summary section at
        // all: the gate moved to the chat, where the summary would have been
        // (#8860), and the error/retry branch below would otherwise offer
        // them a request they cannot use.
        final summarySection = showsSummaries && finished && view.hasFailed
            ? _SummarySection(
                requestSummary: view.canRequest
                    ? controller.activityController.requestSummary
                    : null,
              )
            : null;

        final hasContent = !finished || summarySection != null;

        return AnimatedSize(
          alignment: Alignment.bottomCenter,
          duration: FluffyThemes.animationDuration,
          child: hasContent
              ? Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(top: BorderSide(color: theme.dividerColor)),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        spacing: 12.0,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (summarySection != null)
                            summarySection
                          else if (!finished)
                            _WaitSection(
                              onContinue: controller.room.continueActivity,
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              : SizedBox(),
        );
      },
    );
  }
}

/// The summary failed. The retry asks the bot, so it shows only while the
/// bot is still in the room to answer.
class _SummarySection extends StatelessWidget {
  final Future<void> Function()? requestSummary;

  const _SummarySection({required this.requestSummary});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.school_outlined, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                L10n.of(context).activitySummaryError,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        if (requestSummary != null)
          TextButton(
            onPressed: requestSummary,
            child: Text(L10n.of(context).requestSummaries),
          ),
      ],
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

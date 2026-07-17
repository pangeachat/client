import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/features/subscription/widgets/subscription_paywall.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Bottom status bar for a session the user has finished: shows the waiting
/// state while others are still going, then the summary's loading/error
/// states. Saving is automatic (ActivityAutoSaveService) — there is no manual
/// save step here.
class ActivityFinishedStatusMessage extends StatelessWidget {
  final ChatController controller;

  const ActivityFinishedStatusMessage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!controller.room.hasCompletedRole) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    final l1 = MatrixState.pangeaController.userController.userL1Code;

    final finished = controller.room.isActivityFinished;
    final summary = controller.room.activitySummaryByL1;

    final hasContent =
        !finished || (summary != null && summary.summary == null);

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
                      if (finished) ...[
                        if (summary != null)
                          _SummarySection(
                            summary: summary,
                            fetchSummaries: l1 != null
                                ? () => controller.room.fetchSummaries(l1)
                                : null,
                          ),
                      ] else
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
  }
}

class _SummarySection extends StatelessWidget {
  final ActivitySummaryModel summary;
  final Future<void> Function()? fetchSummaries;

  const _SummarySection({required this.summary, required this.fetchSummaries});

  @override
  Widget build(BuildContext context) {
    if (summary.summary != null) {
      return const SizedBox.shrink();
    }

    if (summary.isLoading) {
      return Column(
        spacing: 12,
        children: [
          Text(
            L10n.of(context).generatingSummary,
            style: const TextStyle(fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
          const SizedBox(
            height: 36,
            width: 36,
            child: CircularProgressIndicator(),
          ),
        ],
      );
    }

    if (!MatrixState
        .pangeaController
        .subscriptionController
        .showSubscriptionGatedContent) {
      return ErrorIndicator(
        message: L10n.of(context).subscribeToUnlockActivitySummaries,
        onTap: () {
          SubscriptionPaywall.show(
            context,
            userID: Matrix.of(context).client.userID,
          );
        },
      );
    }

    if (summary.hasError) {
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
          TextButton(
            onPressed: fetchSummaries,
            child: Text(L10n.of(context).requestSummaries),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
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

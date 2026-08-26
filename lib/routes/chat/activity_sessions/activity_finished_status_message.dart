import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
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

    final l1 = MatrixState.pangeaController.userController.userL1Code;

    final finished = controller.room.isActivityFinished;

    return ValueListenableBuilder(
      valueListenable: controller.activityController.summaryFetchFailed,
      builder: (context, fetchFailed, _) {
        final summary = controller.room.visibleActivitySummaryByL1;

        // A summary still generating renders in the chat instead, so the bar
        // stays collapsed and the rating card above it doesn't get pushed
        // around (#8018). A locally-recorded failure overrides room state,
        // which can't say "error" when the network is down (#8362).
        final summarySection =
            finished &&
                (fetchFailed ||
                    (summary != null &&
                        summary.summary == null &&
                        !summary.isLoading))
            ? _SummarySection(
                hasError: fetchFailed || (summary?.hasError ?? false),
                fetchSummaries: l1 != null
                    ? controller.activityController.fetchSummaries
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

class _SummarySection extends StatelessWidget {
  final bool hasError;
  final Future<void> Function()? fetchSummaries;

  const _SummarySection({required this.hasError, required this.fetchSummaries});

  @override
  Widget build(BuildContext context) {
    if (!MatrixState
        .pangeaController
        .subscriptionController
        .showSubscriptionGatedContent) {
      return ErrorIndicator(
        message: L10n.of(context).subscribeToUnlockActivitySummaries,
        onTap: () => context.go(
          WorkspaceNav.openSettings(
            GoRouterState.of(context).uri,
            page: 'subscription',
          ),
        ),
      );
    }

    if (hasError) {
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

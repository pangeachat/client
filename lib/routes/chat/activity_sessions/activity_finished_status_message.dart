import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityFinishedStatusMessage extends StatelessWidget {
  final ChatController controller;

  const ActivityFinishedStatusMessage({super.key, required this.controller});

  void _onArchive(BuildContext context) {
    _archiveToAnalytics();
    context.go(
      "/rooms/spaces/${controller.room.courseParent!.id}/details?tab=course",
    );
  }

  Future<void> _archiveToAnalytics() async {
    try {
      final activityPlan = controller.room.activityPlan;
      if (activityPlan == null) {
        throw Exception("No activity plan found for room");
      }

      GoogleAnalytics.completeActivity(
        activityPlan.activityId,
        controller.room.id,
      );

      final lang = activityPlan.req.targetLanguage.split("-").first;
      final langModel = PLanguageStore.byLangCode(lang)!;
      await controller.room.archiveActivity();
      await MatrixState
          .pangeaController
          .matrixState
          .analyticsDataService
          .updateService
          .sendActivityAnalytics(controller.room.id, langModel);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'roomId': controller.room.id});
    }
  }

  ActivitySummaryModel? get summary => controller.room.activitySummaryByL1;

  bool get _enableArchive =>
      summary?.summary != null || summary?.hasError == true;

  @override
  Widget build(BuildContext context) {
    if (!controller.room.hasCompletedRole) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    final isSubscribed =
        MatrixState.pangeaController.subscriptionController.isSubscribed !=
        false;

    final l1 = MatrixState.pangeaController.userController.userL1Code;

    final finished = controller.room.isActivityFinished;
    final archived = controller.room.hasArchivedActivity;
    final summary = controller.room.activitySummaryByL1;

    final hasContent =
        !finished || !archived || (summary != null && summary.summary == null);

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
                            isSubscribed: isSubscribed,
                            fetchSummaries: l1 != null
                                ? () => controller.room.fetchSummaries(l1)
                                : null,
                          ),
                        if (!archived)
                          _ArchiveSection(
                            enabled: _enableArchive,
                            onArchive: () => _onArchive(context),
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
  final bool isSubscribed;
  final ActivitySummaryModel summary;
  final Future<void> Function()? fetchSummaries;

  const _SummarySection({
    required this.isSubscribed,
    required this.summary,
    required this.fetchSummaries,
  });

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

    if (!isSubscribed) {
      return ErrorIndicator(
        message: L10n.of(context).subscribeToUnlockActivitySummaries,
        onTap: () {
          MatrixState.pangeaController.subscriptionController.showPaywall(
            context,
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

class _ArchiveSection extends StatelessWidget {
  final bool enabled;
  final VoidCallback onArchive;

  const _ArchiveSection({required this.enabled, required this.onArchive});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      spacing: 12,
      children: [
        Text(
          L10n.of(context).saveActivityDesc,
          style: const TextStyle(fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
        ElevatedButton(
          onPressed: enabled ? onArchive : null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
          child: Row(
            spacing: 12,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.radar, size: 20),
              Text(
                L10n.of(context).saveActivityTitle,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
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

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
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

  ActivitySummaryModel? get summary => controller.room.activitySummary;

  bool get _enableArchive =>
      summary?.summary != null || summary?.hasError == true;

  @override
  Widget build(BuildContext context) {
    if (!controller.room.hasCompletedRole ||
        controller.room.hasArchivedActivity) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isSubscribed =
        MatrixState.pangeaController.subscriptionController.isSubscribed !=
        false;

    return Container(
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
              AnimatedSize(
                duration: FluffyThemes.animationDuration,
                alignment: Alignment.topCenter,
                child: _SummarySection(
                  controller: controller,
                  isSubscribed: isSubscribed,
                ),
              ),
              if (controller.room.isActivityFinished &&
                  !controller.room.hasArchivedActivity)
                _ArchiveSection(
                  enabled: _enableArchive,
                  onArchive: () => _onArchive(context),
                ),
              if (!controller.room.isActivityFinished)
                _WaitSection(onContinue: controller.room.continueActivity),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  final ChatController controller;
  final bool isSubscribed;

  const _SummarySection({required this.controller, required this.isSubscribed});

  ActivitySummaryModel? get summary => controller.room.activitySummary;

  @override
  Widget build(BuildContext context) {
    if (!controller.room.isActivityFinished) {
      return const SizedBox.shrink();
    }

    if (summary?.summary != null) {
      return const SizedBox.shrink();
    }

    if (summary?.isLoading ?? false) {
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

    if (summary?.hasError ?? false) {
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
            onPressed: controller.room.fetchSummaries,
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
            foregroundColor: theme.colorScheme.onSurface,
            backgroundColor: theme.colorScheme.surface,
            side: BorderSide(color: theme.colorScheme.primaryContainer),
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

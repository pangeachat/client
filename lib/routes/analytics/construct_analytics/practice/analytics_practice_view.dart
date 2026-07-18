import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics_data/analytics_init_error_indicator.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_page.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_repo.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/completed_analytics_practice_exercises_view.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/insufficient_data_indicator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/ongoing_analytics_practice_session_view.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_timer_widget.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/unsubscribed_practice_page.dart';
import 'package:fluffychat/widgets/animated_progress_bar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';

/// The practice panel: a nav header (close = silent leave, title, feedback
/// flag, explicit End control) with the session's progress bar + wall-clock
/// timer riding at the top of the BODY — session state, not navigation. See
/// routing.instructions.md § Practice is a persistent background session.
class AnalyticsPracticeView extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const AnalyticsPracticeView(this.controller, {super.key});

  Widget _headerActions(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller.practiceExerciseState,
    builder: (context, state, _) {
      final session = controller.session.session;
      final hasUnfinishedSession =
          session != null &&
          !session.isComplete &&
          controller.session.sessionError == null;

      return ListenableBuilder(
        listenable: controller.notifier,
        builder: (context, _) {
          final exercise = controller.practiceExercise;
          final flagEnabled =
              exercise != null &&
              !controller.notifier.exerciseComplete(exercise);

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: L10n.of(context).feedbackButton,
                icon: const Icon(Icons.flag_outlined),
                onPressed: flagEnabled
                    ? () => controller.flagExercise(exercise)
                    : null,
              ),
              if (hasUnfinishedSession)
                IconButton(
                  tooltip: L10n.of(context).endPractice,
                  // The same leave affordance as leaving a chat.
                  icon: const Icon(Icons.logout_outlined),
                  onPressed: controller.endSession,
                ),
            ],
          );
        },
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: controller.widget.closeTooltip,
          icon: Icon(controller.widget.closeIcon),
          // Silent leave: the session stays alive in the holder.
          onPressed: controller.widget.close,
        ),
        title: Text(L10n.of(context).practice),
        actions: [_headerActions(context)],
      ),
      body: _body(context),
    );
  }

  /// Progress + timer are session state, not navigation — they ride at the
  /// top of the body, inside the same width constraints as the page content.
  Widget _progressAndTimer(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
    child: Row(
      spacing: 8.0,
      children: [
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: controller.progress,
            builder: (context, progress, _) => AnimatedProgressBar(
              height: 20.0,
              widthPercent: progress,
              barColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: controller.practiceExerciseState,
          builder: (context, state, _) {
            final session = controller.session.session;
            return PracticeTimerWidget(
              key: ValueKey(session?.startedAt ?? DateTime(0)),
              startedAt: session?.startedAt,
              frozenSeconds: session?.state.elapsedSeconds ?? 0,
              onTimeUpdate: controller.session.updateElapsedTime,
              isRunning:
                  session != null &&
                  !session.isComplete &&
                  controller.session.sessionError == null,
            );
          },
        ),
      ],
    ),
  );

  Widget _body(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: MaxWidthBody(
        withScrolling: false,
        showBorder: false,
        padding: EdgeInsets.only(left: 32.0, right: 32.0),
        addVerticalPadding: false,
        child: Column(
          children: [
            _progressAndTimer(context),
            Expanded(child: _content(context)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    const loading = Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator.adaptive(),
      ),
    );
    // Rebuild on every session-flow transition: a load left in flight by
    // a closed panel lands through this notifier, so a reopened panel
    // renders it without this State's setState.
    return ValueListenableBuilder(
      valueListenable: controller.practiceExerciseState,
      builder: (context, _, _) {
        final error = controller.session.sessionError;
        if (error != null) {
          if (error is InsufficientDataException) {
            return InsufficientDataIndicator();
          }

          return error is UnsubscribedException
              ? const UnsubscribedPracticePage()
              : AnalyticsInitErrorIndicator(
                  reinitialize: controller.startSession,
                );
        }

        final session = controller.session.session;
        if (session != null) {
          return session.isComplete && !session.loadFailed
              ? CompletedAnalyticsPracticeExercisesView(
                  session: session,
                  launchSession: controller.startSession,
                  levelProgress: controller.levelProgress,
                )
              : OngoingAnalyticsPracticeSessionView(controller);
        }

        return loading;
      },
    );
  }
}

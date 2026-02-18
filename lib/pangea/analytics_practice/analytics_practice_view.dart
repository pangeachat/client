import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/analytics_practice/completed_activity_session_view.dart';
import 'package:fluffychat/pangea/analytics_practice/ongoing_activity_session_view.dart';
import 'package:fluffychat/pangea/analytics_practice/practice_timer_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/unsubscribed_practice_page.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';

class AnalyticsPracticeView extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const AnalyticsPracticeView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    const loading = Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator.adaptive(),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Row(
          spacing: 8.0,
          children: [
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: controller.progressNotifier,
                builder: (context, progress, _) {
                  return AnimatedProgressBar(
                    height: 20.0,
                    widthPercent: progress,
                    barColor: Theme.of(context).colorScheme.primary,
                  );
                },
              ),
            ),
            //keep track of state to update timer
            ValueListenableBuilder(
              valueListenable: controller.sessionState,
              builder: (context, state, _) {
                if (state is AsyncLoaded<AnalyticsPracticeSessionModel>) {
                  return PracticeTimerWidget(
                    key: ValueKey(state.value.startedAt),
                    initialSeconds: state.value.state.elapsedSeconds,
                    onTimeUpdate: controller.updateElapsedTime,
                    isRunning: !state.value.isComplete,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: MaxWidthBody(
          withScrolling: false,
          showBorder: false,
          child: ValueListenableBuilder(
            valueListenable: controller.sessionState,
            builder: (context, state, _) {
              return switch (state) {
                AsyncError<AnalyticsPracticeSessionModel>(:final error) =>
                  error is UnsubscribedException
                      ? const UnsubscribedPracticePage()
                      : ErrorIndicator(
                          message: error.toLocalizedString(context),
                        ),
                AsyncLoaded<AnalyticsPracticeSessionModel>(:final value) =>
                  value.isComplete
                      ? CompletedActivitySessionView(state.value, controller)
                      : OngoingActivitySessionView(controller),
                _ => loading,
              };
            },
          ),
        ),
      ),
    );
  }
}

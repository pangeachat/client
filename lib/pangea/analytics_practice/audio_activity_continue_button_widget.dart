import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class AudioContinueButton extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const AudioContinueButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.activityState,
      builder: (context, state, _) {
        // Only show for audio activities
        if (state is! AsyncLoaded<MultipleChoicePracticeActivityModel>) {
          return const SizedBox.shrink();
        }

        final activity = state.value;
        if (activity.activityType != ActivityTypeEnum.lemmaAudio) {
          return const SizedBox.shrink();
        }

        final totalAnswers = activity.multipleChoiceContent.answers.length;

        return ListenableBuilder(
          listenable: Listenable.merge([
            controller.showingAudioCompletion,
            controller.correctAnswersSelected,
          ]),
          builder: (context, _) {
            final showingCompletion = controller.showingAudioCompletion.value;
            final correctSelected = controller.correctAnswersSelected.value;

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 8.0,
                children: [
                  // Progress ovals row
                  SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          totalAnswers,
                          (index) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Container(
                                height: 16.0,
                                decoration: BoxDecoration(
                                  color: index < correctSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Continue button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: showingCompletion
                          ? controller.onAudioContinuePressed
                          : null,
                      child: Text(
                        L10n.of(context).continueText,
                        style: const TextStyle(fontSize: 16.0),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

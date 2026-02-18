import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_details_popup/morph_meaning_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class ActivityFeedback extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const ActivityFeedback({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.activityState,
        controller.selectedMorphChoice,
      ]),
      builder: (context, _) {
        final activityState = controller.activityState.value;
        final selectedChoice = controller.selectedMorphChoice.value;

        if (activityState
                is! AsyncLoaded<MultipleChoicePracticeActivityModel> ||
            selectedChoice == null) {
          return const SizedBox.shrink();
        }

        final activity = activityState.value;
        final isWrongAnswer = !activity.multipleChoiceContent.isCorrect(
          selectedChoice.tag,
        );

        if (!isWrongAnswer) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: MorphMeaningWidget(
            feature: selectedChoice.feature,
            tag: selectedChoice.tag,
            blankErrorFeedback: true,
          ),
        );
      },
    );
  }
}

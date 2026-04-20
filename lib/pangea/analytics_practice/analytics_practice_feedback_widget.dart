import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_details_popup/morph_meaning_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';

class AnalyticsPracticeExerciseFeedback extends StatelessWidget {
  final MultipleChoicePracticeExerciseModel analyticsPracticeExercise;
  final SelectedMorphChoice selectedChoice;

  const AnalyticsPracticeExerciseFeedback({
    super.key,
    required this.analyticsPracticeExercise,
    required this.selectedChoice,
  });

  @override
  Widget build(BuildContext context) {
    final isWrongAnswer = !analyticsPracticeExercise.multipleChoiceContent
        .isCorrect(selectedChoice.tag);

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
  }
}

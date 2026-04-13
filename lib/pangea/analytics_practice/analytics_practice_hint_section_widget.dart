import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/pangea/analytics_details_popup/morph_meaning_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_hint_button_widget.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';

class AnalyticsPracticeExerciseHintSection extends StatelessWidget {
  final MultipleChoicePracticeExerciseModel analyticsPracticeExercise;
  final VoidCallback onPressed;
  final bool enabled;
  final bool hintPressed;

  const AnalyticsPracticeExerciseHintSection({
    super.key,
    required this.analyticsPracticeExercise,
    required this.onPressed,
    required this.enabled,
    required this.hintPressed,
  });

  @override
  Widget build(BuildContext context) {
    final exercise = analyticsPracticeExercise;

    return switch (exercise) {
      VocabAudioPracticeExerciseModel() => Container(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        constraints: const BoxConstraints(minHeight: 50.0),
        child: HintButton(
          onPressed: onPressed,
          depressed: hintPressed,
          icon: Symbols.text_to_speech,
        ),
      ),
      MorphPracticeExerciseModel() => Container(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        constraints: const BoxConstraints(minHeight: 50.0),
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: hintPressed
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: HintButton(
            icon: Icons.lightbulb_outline,
            onPressed: enabled ? onPressed : () {},
            depressed: !enabled,
          ),
          secondChild: MorphMeaningWidget(
            feature: exercise.morphFeature,
            tag: exercise.multipleChoiceContent.answers.first,
          ),
        ),
      ),
      GrammarErrorPracticeExerciseModel() => Container(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        constraints: const BoxConstraints(minHeight: 50.0),
        child: HintButton(
          icon: Icons.lightbulb_outline,
          onPressed: !enabled ? () {} : onPressed,
          depressed: hintPressed || !enabled,
        ),
      ),
      _ => SizedBox(),
    };
  }
}

import 'package:flutter/widgets.dart';

import 'package:fluffychat/pangea/analytics_practice/choice_cards/audio_choice_card.dart';
import 'package:fluffychat/pangea/analytics_practice/choice_cards/game_choice_card.dart';
import 'package:fluffychat/pangea/analytics_practice/choice_cards/grammar_choice_card.dart';
import 'package:fluffychat/pangea/analytics_practice/choice_cards/meaning_choice_card.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsPracticeExerciseChoiceCard extends StatelessWidget {
  final MultipleChoicePracticeExerciseModel analyticsPracticeExercise;
  final String choiceId;
  final String targetId;
  final VoidCallback onPressed;
  final double cardHeight;

  final String choiceText;
  final String? choiceEmoji;
  final bool enabled;
  final bool shrinkWrap;
  final bool showHint;

  const AnalyticsPracticeExerciseChoiceCard({
    super.key,
    required this.analyticsPracticeExercise,
    required this.choiceId,
    required this.targetId,
    required this.onPressed,
    required this.cardHeight,
    required this.choiceText,
    required this.choiceEmoji,
    required this.showHint,
    this.enabled = true,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    final isCorrect = analyticsPracticeExercise.multipleChoiceContent.isCorrect(
      choiceId,
    );
    final exerciseType = analyticsPracticeExercise.exerciseType;
    final constructId = analyticsPracticeExercise.tokens.first.vocabConstructID;

    switch (analyticsPracticeExercise.exerciseType) {
      case PracticeExerciseTypeEnum.lemmaMeaning:
        return MeaningChoiceCard(
          key: ValueKey(
            '${constructId.string}_${exerciseType.name}_meaning_$choiceId',
          ),
          choiceId: choiceId,
          targetId: targetId,
          displayText: choiceText,
          emoji: choiceEmoji,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: enabled,
        );

      case PracticeExerciseTypeEnum.lemmaAudio:
        return AudioChoiceCard(
          key: ValueKey(
            '${constructId.string}_${exerciseType.name}_audio_$choiceId',
          ),
          choiceId: choiceId,
          targetId: targetId,
          displayText: choiceText,
          textLanguage: MatrixState.pangeaController.userController.userL2!,
          onPressed: onPressed,
          isCorrect: isCorrect,
          isEnabled: enabled,
          showHint: showHint,
        );

      case PracticeExerciseTypeEnum.grammarCategory:
        return GrammarChoiceCard(
          key: ValueKey(
            '${constructId.string}_${exerciseType.name}_grammar_$choiceId',
          ),
          choiceId: choiceId,
          targetId: targetId,
          feature: (analyticsPracticeExercise as MorphPracticeExerciseModel)
              .morphFeature,
          tag: choiceText,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          enabled: enabled,
        );

      case PracticeExerciseTypeEnum.grammarError:
        final exercise =
            analyticsPracticeExercise as GrammarErrorPracticeExerciseModel;
        return GameChoiceCard(
          key: ValueKey(
            '${exercise.errorLength}_${exercise.errorOffset}_${exercise.eventID}_${exerciseType.name}_grammar_error_$choiceId',
          ),
          shouldFlip: false,
          targetId: targetId,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: enabled,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(choiceText),
          ),
        );

      default:
        return GameChoiceCard(
          key: ValueKey(
            '${constructId.string}_${exerciseType.name}_basic_$choiceId',
          ),
          shouldFlip: false,
          targetId: targetId,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: enabled,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(choiceText),
          ),
        );
    }
  }
}

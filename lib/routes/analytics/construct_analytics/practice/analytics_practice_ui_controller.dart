import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

class AnalyticsPracticeUiController {
  static String getChoiceTargetId(String choiceId, ConstructTypeEnum type) =>
      '${type.name}-choice-card-${choiceId.replaceAll(' ', '_')}';

  /// Speak the lemma behind a tapped choice. Wrong taps flip the card to
  /// reveal that lemma, so the reveal gets audio too, not just the correct
  /// answer (#8277).
  static void playChoiceAudio(
    MultipleChoicePracticeExerciseModel exercise,
    String choiceId,
    String language,
  ) {
    if (exercise is! VocabMeaningPracticeExerciseModel) return;

    final cId = ConstructIdentifier.fromString(choiceId);
    if (cId == null) return;
    TtsController.tryToSpeak(
      cId.lemma,
      langCode: language,
      useCase: TtsUseCase.choices,
      pos: cId.category,
    );
  }

  static void playTargetAudio(
    MultipleChoicePracticeExerciseModel exercise,
    ConstructTypeEnum type,
    String language,
  ) {
    if (exercise is! VocabMeaningPracticeExerciseModel) return;

    final token = exercise.tokens.first;
    TtsController.tryToSpeak(
      token.vocabConstructID.lemma,
      langCode: language,
      useCase: TtsUseCase.choices,
      pos: token.pos,
      morph: token.morph.map((k, v) => MapEntry(k.name, v)),
    );
  }
}

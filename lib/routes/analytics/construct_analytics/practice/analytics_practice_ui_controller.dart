import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

class AnalyticsPracticeUiController {
  static String getChoiceTargetId(String choiceId, ConstructTypeEnum type) =>
      '${type.name}-choice-card-${choiceId.replaceAll(' ', '_')}';

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
      pos: token.pos,
      morph: token.morph.map((k, v) => MapEntry(k.name, v)),
    );
  }
}

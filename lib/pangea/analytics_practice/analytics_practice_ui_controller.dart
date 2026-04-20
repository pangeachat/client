import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/pangea/text_to_speech/tts_controller.dart';

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

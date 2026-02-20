import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/text_to_speech/tts_controller.dart';

class AnalyticsPracticeUiController {
  static String getChoiceTargetId(String choiceId, ConstructTypeEnum type) =>
      '${type.name}-choice-card-${choiceId.replaceAll(' ', '_')}';

  static void playTargetAudio(
    MultipleChoicePracticeActivityModel activity,
    ConstructTypeEnum type,
    String language,
  ) {
    if (activity is! VocabMeaningPracticeActivityModel) return;

    final token = activity.tokens.first;
    TtsController.tryToSpeak(
      token.vocabConstructID.lemma,
      langCode: language,
      pos: token.pos,
      morph: token.morph.map((k, v) => MapEntry(k.name, v)),
    );
  }
}

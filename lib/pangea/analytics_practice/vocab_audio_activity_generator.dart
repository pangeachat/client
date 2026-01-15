import 'package:fluffychat/pangea/practice_activities/lemma_activity_generator.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class VocabAudioActivityGenerator {
  static Future<MessageActivityResponse> get(
    MessageActivityRequest req,
  ) async {
    final token = req.target.tokens.first;
    final choices =
        await LemmaActivityGenerator.lemmaActivityDistractors(token);

    final choicesList = choices.map((c) => c.lemma).toList();
    choicesList.shuffle();

    return MessageActivityResponse(
      activity: VocabAudioPracticeActivityModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoiceActivity(
          choices: choicesList.toSet(),
          answers: {token.lemma.text},
        ),
      ),
    );
  }
}

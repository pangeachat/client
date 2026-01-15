import 'package:fluffychat/pangea/practice_activities/lemma_activity_generator.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class VocabMeaningActivityGenerator {
  static Future<MessageActivityResponse> get(
    MessageActivityRequest req,
  ) async {
    final token = req.targetTokens.first;
    final choices =
        await LemmaActivityGenerator.lemmaActivityDistractors(token);

    if (!choices.contains(token.vocabConstructID)) {
      choices.add(token.vocabConstructID);
    }

    final Set<String> constructIdChoices = choices.map((c) => c.string).toSet();

    return MessageActivityResponse(
      activity: VocabMeaningPracticeActivityModel(
        targetTokens: [token],
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoiceActivity(
          choices: constructIdChoices,
          answers: {token.vocabConstructID.string},
        ),
      ),
    );
  }
}

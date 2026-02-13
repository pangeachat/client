import 'package:fluffychat/pangea/practice_activities/lemma_activity_generator.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class VocabMeaningActivityGenerator {
  static Future<MessageActivityResponse> get(MessageActivityRequest req) async {
    final token = req.target.tokens.first;
    final choices = await LemmaActivityGenerator.lemmaActivityDistractors(
      token,
      language: req.userL2.split('-').first,
    );

    if (!choices.contains(token.vocabConstructID)) {
      choices.add(token.vocabConstructID);
    }

    final Set<String> constructIdChoices = choices.map((c) => c.string).toSet();

    return MessageActivityResponse(
      activity: VocabMeaningPracticeActivityModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoiceActivity(
          choices: constructIdChoices,
          answers: {token.vocabConstructID.string},
        ),
      ),
    );
  }
}

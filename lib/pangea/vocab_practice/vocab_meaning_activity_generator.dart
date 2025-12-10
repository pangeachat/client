import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/practice_activities/lemma_activity_generator.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

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

    final Map<ConstructIdentifier, LemmaInfoResponse> lemmaMeanings = {};
    final List<Future> futures = [];
    for (final choice in choices) {
      final future = choice.getLemmaInfo().then((result) {
        if (result.isError) {
          throw result.error!;
        }
        lemmaMeanings[choice] = result.result!;
      });
      futures.add(future);
    }
    await Future.wait(futures);

    return MessageActivityResponse(
      activity: PracticeActivityModel(
        activityType: req.targetType,
        targetTokens: [token],
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoiceActivity(
          choices: lemmaMeanings.values.map((l) => l.meaning).toSet(),
          answers: {lemmaMeanings[token.vocabConstructID]!.meaning},
        ),
      ),
    );
  }
}

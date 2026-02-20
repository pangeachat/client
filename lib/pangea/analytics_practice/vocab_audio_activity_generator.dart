import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/practice_activities/lemma_activity_generator.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class VocabAudioActivityGenerator {
  static Future<MessageActivityResponse> get(MessageActivityRequest req) async {
    final token = req.target.tokens.first;
    final audioExample = req.audioExampleMessage;

    // Find the matching token in the audio example message to get the correct form
    PangeaToken targetToken = token;
    if (audioExample != null) {
      final matchingToken = audioExample.tokens.firstWhere(
        (t) => t.lemma.text.toLowerCase() == token.lemma.text.toLowerCase(),
        orElse: () => token,
      );
      targetToken = matchingToken;
    }

    final Set<String> answers = {};
    final Set<String> wordsInMessage = {};
    final Set<String> lemmasInMessage = {};
    final List<PangeaToken> answerTokens = [targetToken];

    if (audioExample != null) {
      // Collect all words/lemmas in message and select additional answer words
      final List<PangeaToken> potentialAnswers = [];

      for (final t in audioExample.tokens) {
        wordsInMessage.add(t.text.content.toLowerCase());
        lemmasInMessage.add(t.lemma.text.toLowerCase());

        if (t != targetToken &&
            t.lemma.saveVocab &&
            t.text.content.trim().isNotEmpty) {
          potentialAnswers.add(t);
        }
      }

      // Shuffle and select up to 3 additional answer words
      potentialAnswers.shuffle();
      final otherAnswerTokens = potentialAnswers.take(3).toList();

      answerTokens.addAll(otherAnswerTokens);
      answers.addAll(answerTokens.map((t) => t.text.content.toLowerCase()));
    } else {
      answers.add(targetToken.text.content.toLowerCase());
      wordsInMessage.add(targetToken.text.content.toLowerCase());
      lemmasInMessage.add(targetToken.lemma.text.toLowerCase());
    }

    // Generate distractors, filtering out anything in the message (by form or lemma)
    final choices = await LemmaActivityGenerator.lemmaActivityDistractors(
      targetToken,
      maxChoices: 20,
      language: req.userL2.split('-').first,
    );
    final choicesList = choices
        .map((c) => c.lemma)
        .where(
          (lemma) =>
              !answers.contains(lemma.toLowerCase()) &&
              !wordsInMessage.contains(lemma.toLowerCase()) &&
              !lemmasInMessage.contains(lemma.toLowerCase()),
        )
        .take(4)
        .toList();

    final allChoices = [...choicesList, ...answers];
    allChoices.shuffle();

    return MessageActivityResponse(
      activity: VocabAudioPracticeActivityModel(
        tokens: answerTokens,
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoiceActivity(
          choices: allChoices.toSet(),
          answers: answers,
        ),
        roomId: audioExample?.roomId,
        eventId: audioExample?.eventId,
        exampleMessage:
            audioExample?.exampleMessage ??
            const ExampleMessageInfo(exampleMessage: []),
      ),
    );
  }
}

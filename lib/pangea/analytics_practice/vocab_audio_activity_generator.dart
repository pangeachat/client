import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/practice_activities/lemma_activity_generator.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class VocabAudioActivityGenerator {
  static Future<MessageActivityResponse> get(MessageActivityRequest req) async {
    final token = req.target.tokens.first;
    final audioExample = req.audioExampleMessage;

    final Set<String> answers = {token.text.content.toLowerCase()};
    final Set<String> wordsInMessage = {};
    if (audioExample != null) {
      for (final t in audioExample.tokens) {
        wordsInMessage.add(t.text.content.toLowerCase());
      }

      // Extract up to 3 additional words as answers, from shuffled message
      audioExample.tokens.shuffle();
      final otherWords = audioExample.tokens
          .where(
            (t) =>
                t.lemma.saveVocab &&
                t.text.content.toLowerCase() !=
                    token.text.content.toLowerCase() &&
                t.text.content.trim().isNotEmpty,
          )
          .take(3)
          .map((t) => t.text.content.toLowerCase())
          .toList();

      answers.addAll(otherWords);
    }

    // Generate distractors, filtering out anything in the message or answers
    final choices = await LemmaActivityGenerator.lemmaActivityDistractors(
      token,
      maxChoices: 20,
    );
    final choicesList = choices
        .map((c) => c.lemma)
        .where(
          (lemma) =>
              !answers.contains(lemma.toLowerCase()) &&
              !wordsInMessage.contains(lemma.toLowerCase()),
        )
        .take(4)
        .toList();

    final allChoices = [...choicesList, ...answers];
    allChoices.shuffle();

    return MessageActivityResponse(
      activity: VocabAudioPracticeActivityModel(
        tokens: req.target.tokens,
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

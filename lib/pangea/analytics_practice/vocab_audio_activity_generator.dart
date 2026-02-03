import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/practice_activities/lemma_activity_generator.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class VocabAudioActivityGenerator {
  static Future<MessageActivityResponse> get(
    MessageActivityRequest req,
  ) async {
    final token = req.target.tokens.first;
    final audioExample = req.audioExampleMessage;

    final Set<String> answers = {token.lemma.text};
    final Set<String> wordsInMessage = {};
    if (audioExample != null) {
      // Collect all text content and lemmas from the message
      for (final t in audioExample.tokens) {
        wordsInMessage.add(t.text.content.toLowerCase());
        wordsInMessage.add(t.lemma.text.toLowerCase());
      }

      // Extract up to 3 additional words as answers
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
    final choices =
        await LemmaActivityGenerator.lemmaActivityDistractors(token);
    final choicesList = choices
        .map((c) => c.lemma)
        .where(
          (lemma) =>
              !answers.contains(lemma.toLowerCase()) &&
              !wordsInMessage.contains(lemma.toLowerCase()),
        )
        .take(10)
        .toList();

    choicesList.shuffle();

    // Ensure we have enough choices (at least 4 distractors)
    if (choicesList.length < 4) {
      final allChoices = choices
          .map((c) => c.lemma)
          .where((lemma) => !answers.contains(lemma.toLowerCase()))
          .toList();
      allChoices.shuffle();
      choicesList.addAll(
        allChoices.take(4 - choicesList.length),
      );
    }

    final allChoices = [...choicesList, ...answers];

    debugPrint(
      'VocabAudioActivityGenerator: Generated choices: $allChoices, answers: $answers',
    );

    return MessageActivityResponse(
      activity: VocabAudioPracticeActivityModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoiceActivity(
          choices: allChoices.toSet(),
          answers: answers,
        ),
        audioExampleMessage: audioExample,
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/pangea/practice_exercises/multiple_choice_practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';

class GrammarErrorPracticeGenerator {
  static Future<MessagePracticeExerciseResponse> get(
    MessagePracticeExerciseRequest req,
  ) async {
    assert(
      req.grammarErrorInfo != null,
      'Grammar error info must be provided for grammar error practice',
    );

    final choreo = req.grammarErrorInfo!.choreo;
    final stepIndex = req.grammarErrorInfo!.stepIndex;
    final eventID = req.grammarErrorInfo!.eventID;

    final igcMatch =
        choreo.choreoSteps[stepIndex].acceptedOrIgnoredMatch?.match;
    assert(igcMatch?.choices != null, 'IGC match must have choices');
    assert(igcMatch?.bestChoice != null, 'IGC match must have a best choice');

    final correctChoice = igcMatch!.bestChoice!.value;
    final choices = igcMatch.choices!.map((c) => c.value).toList();

    final stepText = choreo.stepText(stepIndex: stepIndex - 1);
    final errorSpan = stepText.characters
        .skip(igcMatch.offset)
        .take(igcMatch.length)
        .toString();

    if (!req.grammarErrorInfo!.translation.contains(errorSpan)) {
      choices.add(errorSpan);
    }

    if (igcMatch.offset + igcMatch.length > stepText.characters.length) {
      // Sometimes choreo records turn out weird when users edit the message
      // mid-IGC. If the offsets / lengths don't make sense, skip this target.
      throw Exception(
        "IGC match offset and length exceed step text length. Step text: '$stepText', match offset: ${igcMatch.offset}, match length: ${igcMatch.length}",
      );
    }

    choices.shuffle();
    return MessagePracticeExerciseResponse(
      exercise: GrammarErrorPracticeExerciseModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoicePracticeExercise(
          choices: choices.toSet(),
          answers: {correctChoice},
        ),
        text: stepText,
        errorOffset: igcMatch.offset,
        errorLength: igcMatch.length,
        eventID: eventID,
        translation: req.grammarErrorInfo!.translation,
      ),
    );
  }
}

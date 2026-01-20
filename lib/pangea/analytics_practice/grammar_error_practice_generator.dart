import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class GrammarErrorPracticeGenerator {
  static Future<MessageActivityResponse> get(
    MessageActivityRequest req,
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

    choices.add(errorSpan);
    choices.shuffle();
    return MessageActivityResponse(
      activity: GrammarErrorPracticeActivityModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoiceActivity(
          choices: choices.toSet(),
          answers: {correctChoice},
        ),
        text: stepText,
        errorOffset: igcMatch.offset,
        errorLength: igcMatch.length,
        eventID: eventID,
      ),
    );
  }
}

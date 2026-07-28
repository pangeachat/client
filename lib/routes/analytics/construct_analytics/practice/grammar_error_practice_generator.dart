import 'package:flutter/material.dart';

import 'package:fluffychat/routes/chat/toolbar/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/multiple_choice_practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

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

    // Display the sentence off igcMatch.fullText and blank the target span in
    // it. The offset indexes fullText correctly, but the blank length must be
    // derived from the accepted correction (bestChoice), NOT igcMatch.length: on
    // accept, IgcController._applyReplacement overwrites fullText with the
    // CORRECTED sentence, and for messages sent before the 2026-02-25 length fix
    // (#5655) it left `length` at the pre-correction span length. Trusting that
    // stale length under-covers the blank by the correction's length delta,
    // orphaning the tail of the target word (e.g. the "n" of "están").
    // bestChoice.value is exactly the corrected span sitting at `offset`, so it
    // aligns the blank for both old and new records; fall back to the stored
    // length only if that span isn't present (malformed record) (#7360).
    final baseText = igcMatch.fullText;
    final baseChars = baseText.characters;
    final blankLength = targetBlankLength(
      baseText: baseText,
      offset: igcMatch.offset,
      correctChoice: correctChoice,
      storedLength: igcMatch.length,
    );
    final errorSpan = baseChars
        .skip(igcMatch.offset)
        .take(blankLength)
        .toString();

    if (!req.grammarErrorInfo!.translation.contains(errorSpan)) {
      choices.add(errorSpan);
    }

    if (igcMatch.offset + blankLength > baseChars.length) {
      // Sometimes choreo records turn out weird when users edit the message
      // mid-IGC. If the offsets / lengths don't make sense, skip this target.
      throw Exception(
        "IGC match offset and span exceed base text length. Base text: '$baseText', match offset: ${igcMatch.offset}, span length: $blankLength",
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
        text: baseText,
        errorOffset: igcMatch.offset,
        errorLength: blankLength,
        eventID: eventID,
        translation: req.grammarErrorInfo!.translation,
      ),
    );
  }

  /// The number of graphemes the blank should span in [baseText] starting at
  /// [offset]. Prefers the length of the accepted correction [correctChoice] —
  /// the true corrected span sitting at [offset] in fullText — over
  /// [storedLength]. On accept, `IgcController._applyReplacement` overwrites the
  /// match's fullText with the corrected sentence; for messages sent before the
  /// 2026-02-25 length fix (#5655) it left `length` at the pre-correction span
  /// length, which under-covers the blank by the correction's length delta and
  /// orphans the tail of the target word (e.g. the "n" of "están"). Falls back
  /// to [storedLength] when the corrected span isn't present at [offset]
  /// (malformed record) (#7360).
  @visibleForTesting
  static int targetBlankLength({
    required String baseText,
    required int offset,
    required String correctChoice,
    required int storedLength,
  }) {
    final correctChoiceLength = correctChoice.characters.length;
    final spanAtOffset = baseText.characters
        .skip(offset)
        .take(correctChoiceLength)
        .toString();
    return spanAtOffset == correctChoice ? correctChoiceLength : storedLength;
  }
}

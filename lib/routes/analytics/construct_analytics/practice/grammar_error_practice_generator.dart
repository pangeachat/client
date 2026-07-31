import 'package:flutter/material.dart';

import 'package:fluffychat/routes/chat/choreographer/choreo_edit_model.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_record_model.dart';
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

    final example = resolveExample(
      choreo: choreo,
      stepIndex: stepIndex,
      matchOffset: igcMatch.offset,
      storedLength: igcMatch.length,
      correctChoice: correctChoice,
      sentText: req.grammarErrorInfo!.sentText,
      fallbackText: igcMatch.fullText,
    );

    // Offer the learner's own pre-correction text as a distractor — the whole
    // point of the exercise is choosing between it and the correction. Skipped
    // when it already appears in the L1 translation printed under the sentence.
    final errorSpan = originalErrorSpan(
      choreo: choreo,
      stepIndex: stepIndex,
      matchOffset: igcMatch.offset,
      correctChoice: correctChoice,
    );
    if (errorSpan != null &&
        !req.grammarErrorInfo!.translation.contains(errorSpan)) {
      choices.add(errorSpan);
    }

    if (example.offset + example.length > example.text.characters.length) {
      // Sometimes choreo records turn out weird when users edit the message
      // mid-IGC. If the offsets / lengths don't make sense, skip this target.
      throw Exception(
        "IGC match offset and span exceed base text length. Base text: '${example.text}', match offset: ${example.offset}, span length: ${example.length}",
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
        text: example.text,
        errorOffset: example.offset,
        errorLength: example.length,
        eventID: eventID,
        translation: req.grammarErrorInfo!.translation,
      ),
    );
  }

  /// The sentence to show the learner, and where the blank goes in it
  /// (grapheme-indexed, as `GrammarErrorExampleWidget.splitAroundBlank` wants).
  ///
  /// The example must read as the message the learner actually sent — every
  /// accepted writing-assistance correction applied, with just this one span
  /// blanked (#8044). The match's own `fullText` is not that sentence: on
  /// accept, `IgcController._applyReplacement` rewrites it to the text as of
  /// that single replacement, so a step-0 match still carries every later error.
  /// For a learner writing in their L1 and accepting suggestions one at a time,
  /// that reads as English.
  ///
  /// So the target span is walked forward out of `stepText(stepIndex)` and into
  /// [sentText]. Anything that makes the walk unsafe — a later edit overlapping
  /// the span, a malformed legacy record, no sent text on a restored session —
  /// falls back to [fallbackText] (the old behavior), so no target is ever lost.
  @visibleForTesting
  static ({String text, int offset, int length}) resolveExample({
    required ChoreoRecordModel choreo,
    required int stepIndex,
    required int matchOffset,
    required int storedLength,
    required String correctChoice,
    required String? sentText,
    required String fallbackText,
  }) {
    final fallback = (
      text: fallbackText,
      offset: matchOffset,
      length: targetBlankLength(
        baseText: fallbackText,
        offset: matchOffset,
        correctChoice: correctChoice,
        storedLength: storedLength,
      ),
    );

    if (sentText == null || sentText.isEmpty) return fallback;
    if (stepIndex < 0 || stepIndex >= choreo.choreoSteps.length) {
      return fallback;
    }

    try {
      final blankLength = targetBlankLength(
        baseText: choreo.stepText(stepIndex: stepIndex),
        offset: matchOffset,
        correctChoice: correctChoice,
        storedLength: storedLength,
      );

      final mapped = mapSpanToSentText(
        choreo: choreo,
        stepIndex: stepIndex,
        offset: matchOffset,
        length: blankLength,
        sentText: sentText,
      );
      if (mapped == null) return fallback;

      // The mapped span must still be the accepted correction. If it isn't, the
      // learner reworked that stretch of text afterwards and the walk landed
      // somewhere else — better the old sentence than a misplaced blank.
      final mappedSpan = sentText.characters
          .skip(mapped.offset)
          .take(mapped.length)
          .toString();
      if (mappedSpan != correctChoice) return fallback;

      return (text: sentText, offset: mapped.offset, length: mapped.length);
    } on RangeError {
      return fallback;
    }
  }

  /// Walks the span at [offset]/[length] in `stepText(stepIndex)` forward
  /// through every later choreo edit, landing it in [sentText]. Null when a
  /// later edit overlaps the span, or when the result doesn't sit on grapheme
  /// boundaries.
  ///
  /// [ChoreoEditModel] offsets are code units, while match offsets and the
  /// blank renderer are graphemes — so the walk runs entirely in code units and
  /// converts back exactly once, at the end. Mixing the two is the class of bug
  /// #7360 already was.
  @visibleForTesting
  static ({int offset, int length})? mapSpanToSentText({
    required ChoreoRecordModel choreo,
    required int stepIndex,
    required int offset,
    required int length,
    required String sentText,
  }) {
    final stepChars = choreo.stepText(stepIndex: stepIndex).characters;
    if (offset < 0 || length < 0 || offset + length > stepChars.length) {
      return null;
    }

    int start = stepChars.take(offset).toString().length;
    int end = start + stepChars.skip(offset).take(length).toString().length;

    for (int i = stepIndex + 1; i < choreo.choreoSteps.length; i++) {
      final edit = choreo.choreoSteps[i].edits;
      if (edit == null) continue;
      final shifted = _shiftSpan(start, end, edit);
      if (shifted == null) return null;
      start = shifted.$1;
      end = shifted.$2;
    }

    // The learner can keep typing after their last correction, so the sent text
    // is not always the last step's text. That trailing difference is one more
    // edit to walk through.
    final lastStepText = choreo.stepText();
    if (lastStepText != sentText) {
      final shifted = _shiftSpan(
        start,
        end,
        ChoreoEditModel.fromText(
          originalText: lastStepText,
          editedText: sentText,
        ),
      );
      if (shifted == null) return null;
      start = shifted.$1;
      end = shifted.$2;
    }

    if (start < 0 || start > end || end > sentText.length) return null;

    final before = sentText.substring(0, start);
    final span = sentText.substring(start, end);
    final beforeLength = before.characters.length;
    final spanLength = span.characters.length;

    // Reject boundaries that landed inside a grapheme cluster.
    if (sentText.characters.take(beforeLength).toString() != before) {
      return null;
    }
    if (sentText.characters.skip(beforeLength).take(spanLength).toString() !=
        span) {
      return null;
    }

    return (offset: beforeLength, length: spanLength);
  }

  /// [start]/[end] (code units) after [edit] is applied to the text they index,
  /// or null if the edit overlaps the span — a step's edit is the minimal
  /// whole-text diff ([ChoreoEditModel.fromText]), so it absorbs any typing the
  /// learner did between steps as well as the correction itself, and can well
  /// cover the span we're tracking.
  static (int, int)? _shiftSpan(int start, int end, ChoreoEditModel edit) {
    if (edit.length == 0 && edit.insert.isEmpty) return (start, end);

    final editEnd = edit.offset + edit.length;
    if (editEnd <= start) {
      final delta = edit.insert.length - edit.length;
      return (start + delta, end + delta);
    }
    if (edit.offset >= end) return (start, end);
    return null;
  }

  /// The learner's own text for this span before the correction — the wrong
  /// answer worth offering alongside the right one.
  ///
  /// Recovered by shifting the corrected span's end back by the step's edit
  /// delta, which is only sound when that edit sits inside the corrected span;
  /// returns null otherwise (the learner typed elsewhere between steps, so the
  /// diff covers more than this correction). Note the stored match `length` is
  /// no use here — `_applyReplacement` overwrites it with the *corrected*
  /// length on accept.
  static String? originalErrorSpan({
    required ChoreoRecordModel choreo,
    required int stepIndex,
    required int matchOffset,
    required String correctChoice,
  }) {
    if (stepIndex < 0 || stepIndex >= choreo.choreoSteps.length) return null;
    final edit = choreo.choreoSteps[stepIndex].edits;
    if (edit == null) return null;

    try {
      final stepText = choreo.stepText(stepIndex: stepIndex);
      final priorText = choreo.stepText(stepIndex: stepIndex - 1);

      final start = stepText.characters.take(matchOffset).toString().length;
      final end = start + correctChoice.length;
      if (end > stepText.length) return null;
      if (stepText.substring(start, end) != correctChoice) return null;

      // Containment also guarantees the text before [start] is untouched by the
      // edit, so [start] indexes priorText the same way it indexes stepText.
      if (edit.offset < start || edit.offset + edit.insert.length > end) {
        return null;
      }

      final priorEnd = end - (edit.insert.length - edit.length);
      if (priorEnd < start || priorEnd > priorText.length) return null;

      final span = priorText.substring(start, priorEnd);
      return span.isEmpty || span == correctChoice ? null : span;
    } on RangeError {
      return null;
    }
  }

  /// The number of graphemes the blank should span in [baseText] starting at
  /// [offset]. Prefers the length of the accepted correction [correctChoice] —
  /// the true corrected span sitting at [offset] — over [storedLength]. On
  /// accept, `IgcController._applyReplacement` rewrites the match's length to
  /// the corrected one; for messages sent before the 2026-02-25 length fix
  /// (#5655) it left `length` at the pre-correction span length, which
  /// under-covers the blank by the correction's length delta and orphans the
  /// tail of the target word (e.g. the "n" of "están"). Falls back to
  /// [storedLength] when the corrected span isn't present at [offset]
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

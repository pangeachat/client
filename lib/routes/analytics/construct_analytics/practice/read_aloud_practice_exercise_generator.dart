import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_match.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_audio_practice_exercise_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_meaning_practice_exercise_generator.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

/// Builds a read-aloud exercise: the example sentence the learner met the
/// target word in, which they read aloud. See
/// practice-exercises.instructions.md, "Speaking practice".
class ReadAloudPracticeExerciseGenerator {
  static Future<MessagePracticeExerciseResponse> get(
    MessagePracticeExerciseRequest req,
  ) async {
    final token = req.target.tokens.first;

    // The example is resolved here, in the eager background queue, like the
    // listening exercise's. Without one there is nothing to read, so the slot
    // becomes a meaning exercise for the same word — the same degradation path
    // the listening exercise takes.
    final example =
        req.audioExampleMessage ??
        await VocabAudioPracticeExerciseGenerator.resolveAudioExample(
          req,
          maxContextChars: _contextChars,
        );
    if (example == null) {
      _reportFallback('no_example', token.lemma.text);
      return VocabMeaningPracticeExerciseGenerator.get(
        VocabAudioPracticeExerciseGenerator.asMeaningRequest(req),
      );
    }

    final exercise = ReadAloudPracticeExerciseModel(
      targetLemma: token.lemma.text,
      exampleTokens: example.tokens,
      langCode: req.userL2,
      roomId: example.roomId,
      eventId: example.eventId,
      exampleMessage: example.exampleMessage,
    );
    // The target has to be among the words read, or nothing can earn the use.
    if (exercise.targetIndex == -1) {
      _reportFallback('target_not_in_example', token.lemma.text);
      return VocabMeaningPracticeExerciseGenerator.get(
        VocabAudioPracticeExerciseGenerator.asMeaningRequest(req),
      );
    }
    return MessagePracticeExerciseResponse(
      exercise: trimToSentence(
        exercise,
        maxWords: AnalyticsPracticeConstants.readAloudMaxWords,
      ),
    );
  }

  /// Enough of the message around the target to hold its whole sentence; the
  /// sentence cut and the word cap below do the rest.
  static const int _contextChars = 400;

  static final RegExp _sentenceEnd = RegExp(r'^[.!?…。！？]+$');
  static final RegExp _sentenceOpen = RegExp(r'^[¿¡]+$');

  static bool _endsSentence(PangeaToken t) =>
      _sentenceEnd.hasMatch(t.text.content.trim());
  static bool _opensSentence(PangeaToken t) =>
      _sentenceOpen.hasMatch(t.text.content.trim());

  /// The sentence of the example that holds the target, whole; a sentence
  /// longer than [maxWords] is cut to a window inside it by [trimToWindow].
  /// A cut at a stop reads naturally; one in the middle of a clause did not.
  @visibleForTesting
  static ReadAloudPracticeExerciseModel trimToSentence(
    ReadAloudPracticeExerciseModel exercise, {
    required int maxWords,
  }) {
    final tokens = exercise.exampleTokens;
    final words = exercise.referenceTokens;
    final target = exercise.targetIndex;
    if (target == -1 || tokens.isEmpty) return exercise;
    final targetAt = tokens.indexWhere((t) => identical(t, words[target]));

    var first = 0;
    for (var i = targetAt - 1; i >= 0; i--) {
      if (_endsSentence(tokens[i])) {
        first = i + 1;
        break;
      }
    }
    var last = tokens.length - 1;
    for (var i = targetAt; i < tokens.length; i++) {
      if (_endsSentence(tokens[i])) {
        last = i;
        break;
      }
    }
    // Stray punctuation left at the front does not open a sentence; an
    // inverted question or exclamation mark does.
    while (first < targetAt &&
        !isSpokenWord(tokens[first].text.content) &&
        !_opensSentence(tokens[first])) {
      first++;
    }

    final sentence = first == 0 && last == tokens.length - 1
        ? exercise
        : _rebuild(
            exercise,
            tokens.sublist(first, last + 1),
            cutBefore: false,
            cutAfter: false,
          );
    if (sentence.referenceTokens.length <= maxWords) return sentence;
    return trimToWindow(sentence, maxWords: maxWords);
  }

  /// At most [maxWords] words of the example around the target, with an
  /// ellipsis where the sentence was cut: a long message is a chore to read
  /// aloud, and the target is the point. Punctuation glued to the last word
  /// stays with it, so a sentence that ends inside the window keeps its stop.
  @visibleForTesting
  static ReadAloudPracticeExerciseModel trimToWindow(
    ReadAloudPracticeExerciseModel exercise, {
    required int maxWords,
  }) {
    final words = exercise.referenceTokens;
    final target = exercise.targetIndex;
    if (words.length <= maxWords || target == -1) return exercise;

    var start = max(0, target - (maxWords - 1) ~/ 2);
    final end = min(words.length, start + maxWords);
    start = max(0, end - maxWords);

    final tokens = exercise.exampleTokens;
    final firstIndex = tokens.indexWhere((t) => identical(t, words[start]));
    var lastIndex = tokens.indexWhere((t) => identical(t, words[end - 1]));
    while (lastIndex + 1 < tokens.length) {
      final last = tokens[lastIndex].text;
      final next = tokens[lastIndex + 1].text;
      final glued =
          next.offset == last.offset + last.content.characters.length &&
          !isSpokenWord(next.content);
      if (!glued) break;
      lastIndex++;
    }
    return _rebuild(
      exercise,
      tokens.sublist(firstIndex, lastIndex + 1),
      cutBefore: start > 0,
      cutAfter: end < words.length,
    );
  }

  /// The same exercise over [window], a contiguous run of its tokens, with
  /// the displayed text sliced to match and an ellipsis on each cut side.
  static ReadAloudPracticeExerciseModel _rebuild(
    ReadAloudPracticeExerciseModel exercise,
    List<PangeaToken> window, {
    required bool cutBefore,
    required bool cutAfter,
  }) {
    final chars = exercise.referenceText.characters.toList();
    final base = exercise.exampleTokens.first.text.offset;
    final from = (window.first.text.offset - base).clamp(0, chars.length);
    final to =
        (window.last.text.offset +
                window.last.text.content.characters.length -
                base)
            .clamp(0, chars.length);

    return ReadAloudPracticeExerciseModel(
      targetLemma: exercise.tokens.first.lemma.text,
      exampleTokens: window,
      langCode: exercise.langCode,
      roomId: exercise.roomId,
      eventId: exercise.eventId,
      exampleMessage: ExampleMessageInfo(
        exampleMessage: [
          if (cutBefore) const TextSpan(text: '… '),
          TextSpan(text: chars.sublist(from, to).join()),
          if (cutAfter) const TextSpan(text: '…'),
        ],
      ),
    );
  }

  /// The swap is a degradation the session hides, since the learner just sees
  /// a meaning exercise, so it reports once per reason rather than silently.
  static void _reportFallback(String reason, String lemma) => unawaited(
    ErrorHandler.logErrorOnce(
      key: 'read_aloud_fallback_$reason',
      e: 'read-aloud target fell back to a meaning exercise: $reason',
      data: {'lemma': lemma},
      level: SentryLevel.warning,
    ),
  );
}

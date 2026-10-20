import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_audio_practice_exercise_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_meaning_practice_exercise_generator.dart';
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
        await VocabAudioPracticeExerciseGenerator.resolveAudioExample(req);
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
    return MessagePracticeExerciseResponse(exercise: exercise);
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

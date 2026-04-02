import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/pangea/practice_exercises/multiple_choice_practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';

class MorphPracticeExerciseGenerator {
  /// Generate a morphological exercise for a given token and morphological feature
  static MessagePracticeExerciseResponse get(
    MessagePracticeExerciseRequest req,
  ) {
    debugger(when: kDebugMode && req.target.tokens.length != 1);

    debugger(when: kDebugMode && req.target.morphFeature == null);

    final PangeaToken token = req.target.tokens.first;

    final MorphFeaturesEnum morphFeature = req.target.morphFeature!;
    final String? morphTag = token.getMorphTag(morphFeature);

    if (morphTag == null) {
      debugger(when: kDebugMode);
      throw "No morph tag found for morph feature";
    }

    final distractors = token.morphPracticeExerciseDistractors(
      morphFeature,
      morphTag,
    );
    distractors.add(morphTag);
    final choices = distractors.toList()..shuffle();

    debugger(when: kDebugMode && distractors.length < 3);

    return MessagePracticeExerciseResponse(
      exercise: MorphMatchPracticeExerciseModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        morphFeature: morphFeature,
        multipleChoiceContent: MultipleChoicePracticeExercise(
          choices: choices.toSet(),
          answers: {morphTag},
        ),
      ),
    );
  }
}

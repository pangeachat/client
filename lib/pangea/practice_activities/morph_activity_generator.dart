import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

typedef MorphActivitySequence = Map<String, POSActivitySequence>;

typedef POSActivitySequence = List<String>;

class MorphActivityGenerator {
  /// Generate a morphological activity for a given token and morphological feature
  static MessageActivityResponse get(
    MessageActivityRequest req,
  ) {
    debugger(when: kDebugMode && req.targetTokens.length != 1);

    debugger(when: kDebugMode && req.targetMorphFeature == null);

    final PangeaToken token = req.targetTokens.first;

    final MorphFeaturesEnum morphFeature = req.targetMorphFeature!;
    final String? morphTag = token.getMorphTag(morphFeature);

    if (morphTag == null) {
      debugger(when: kDebugMode);
      throw "No morph tag found for morph feature";
    }

    final distractors = token.morphActivityDistractors(morphFeature, morphTag);
    distractors.add(morphTag);

    debugger(when: kDebugMode && distractors.length < 3);

    return MessageActivityResponse(
      activity: MorphMatchPracticeActivityModel(
        targetTokens: req.targetTokens,
        langCode: req.userL2,
        morphFeature: morphFeature,
        multipleChoiceContent: MultipleChoiceActivity(
          choices: distractors,
          answers: {morphTag},
        ),
      ),
    );
  }
}

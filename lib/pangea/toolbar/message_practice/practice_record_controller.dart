import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_record.dart';
import 'package:fluffychat/pangea/practice_activities/practice_record_repo.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';

class PracticeRecordController {
  static PracticeRecord recordByActivity(PracticeActivityModel activity) =>
      PracticeRecordRepo.get(activity.practiceTarget);

  static bool isCompleteByTarget(PracticeTarget target) {
    final record = PracticeRecordRepo.get(target);
    if (target.activityType == ActivityTypeEnum.morphId) {
      return record.completeResponses > 0;
    }

    return target.tokens.every(
      (t) => record.responses
          .any((res) => res.cId == t.vocabConstructID && res.isCorrect),
    );
  }

  static bool isCompleteByActivity(PracticeActivityModel activity) {
    final activityRecord = recordByActivity(activity);
    if (activity.activityType == ActivityTypeEnum.morphId) {
      return activityRecord.completeResponses > 0;
    }

    return activity.tokens.every(
      (t) => activityRecord.responses
          .any((res) => res.cId == t.vocabConstructID && res.isCorrect),
    );
  }

  static bool isCompleteByToken(
    PracticeTarget target,
    PangeaToken token, [
    MorphFeaturesEnum? morph,
  ]) {
    final ConstructIdentifier? cId =
        morph == null ? token.vocabConstructID : token.morphIdByFeature(morph);

    if (cId == null) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        m: "isCompleteByToken: cId is null for token ${token.text.content}",
        data: {
          "t": token.toJson(),
          "morph": morph?.name,
        },
      );
      return false;
    }

    final record = PracticeRecordRepo.get(target);
    if (target.activityType == ActivityTypeEnum.morphId) {
      return record.responses.any(
        (res) => res.cId == token.morphIdByFeature(morph!) && res.isCorrect,
      );
    }

    return record.responses.any(
      (res) => res.cId == token.vocabConstructID && res.isCorrect,
    );
  }

  static bool hasAnyCorrectChoices(PracticeTarget target) {
    final record = PracticeRecordRepo.get(target);
    return record.responses.any((response) => response.isCorrect);
  }

  static bool onSelectChoice(
    String choice,
    PangeaToken token,
    PracticeActivityModel activity,
  ) {
    final record = recordByActivity(activity);
    if (isCompleteByActivity(activity) ||
        record.alreadyHasMatchResponse(
          token.vocabConstructID,
          choice,
        )) {
      return false;
    }

    final isCorrect = switch (activity) {
      MatchPracticeActivityModel() => activity.isCorrect(token, choice),
      MultipleChoicePracticeActivityModel() => activity.isCorrect(choice),
    };

    record.addResponse(
      cId: token.vocabConstructID,
      target: activity.practiceTarget,
      text: choice,
      score: isCorrect ? 1 : 0,
    );

    return isCorrect;
  }
}

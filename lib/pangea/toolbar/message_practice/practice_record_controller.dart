import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_choice.dart';
import 'package:fluffychat/pangea/practice_activities/practice_record.dart';
import 'package:fluffychat/pangea/practice_activities/practice_record_repo.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';

class PracticeRecordController {
  static PracticeRecord _recordByTarget(PracticeTarget target) =>
      PracticeRecordRepo.get(target);

  static bool hasResponse(PracticeTarget target) =>
      _recordByTarget(target).responses.isNotEmpty;

  static ActivityRecordResponse? lastResponse(PracticeTarget target) {
    final record = _recordByTarget(target);
    return record.responses.lastOrNull;
  }

  static ActivityRecordResponse? correctResponse(
    PracticeTarget target,
    PangeaToken token,
  ) {
    final record = _recordByTarget(target);
    return record.responses.firstWhereOrNull(
      (res) => res.cId == token.vocabConstructID && res.isCorrect,
    );
  }

  static bool? wasCorrectMatch(
    PracticeTarget target,
    PracticeChoice choice,
  ) {
    final record = _recordByTarget(target);
    for (final response in record.responses) {
      if (response.text == choice.choiceContent && response.isCorrect) {
        return true;
      }
    }
    for (final response in record.responses) {
      if (response.text == choice.choiceContent) {
        return false;
      }
    }
    return null;
  }

  static bool? wasCorrectChoice(
    PracticeTarget target,
    String choice,
  ) {
    final record = _recordByTarget(target);
    for (final response in record.responses) {
      if (response.text == choice) {
        return response.isCorrect;
      }
    }
    return null;
  }

  static bool isCompleteByTarget(PracticeTarget target) {
    final record = _recordByTarget(target);
    if (target.activityType == ActivityTypeEnum.morphId) {
      return record.completeResponses > 0;
    }

    return target.tokens.every(
      (t) => record.responses
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

    final record = _recordByTarget(target);
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
    final record = _recordByTarget(target);
    return record.responses.any((response) => response.isCorrect);
  }

  static bool onSelectChoice(
    String choice,
    PangeaToken token,
    PracticeActivityModel activity,
  ) {
    final record = _recordByTarget(activity.practiceTarget);
    if (isCompleteByTarget(activity.practiceTarget) ||
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

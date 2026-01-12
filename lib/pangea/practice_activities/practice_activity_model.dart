import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_choice.dart';
import 'package:fluffychat/pangea/practice_activities/practice_match.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';

class PracticeActivityModel {
  final List<PangeaToken> targetTokens;
  final ActivityTypeEnum activityType;
  final MorphFeaturesEnum? morphFeature;

  final String langCode;

  final MultipleChoiceActivity? multipleChoiceContent;
  final PracticeMatchActivity? matchContent;

  PracticeActivityModel({
    required this.targetTokens,
    required this.langCode,
    required this.activityType,
    this.morphFeature,
    this.multipleChoiceContent,
    this.matchContent,
  }) {
    if (matchContent == null && multipleChoiceContent == null) {
      debugger(when: kDebugMode);
      throw ("both matchContent and multipleChoiceContent are null in PracticeActivityModel");
    }
    if (matchContent != null && multipleChoiceContent != null) {
      debugger(when: kDebugMode);
      throw ("both matchContent and multipleChoiceContent are not null in PracticeActivityModel");
    }
    if (activityType == ActivityTypeEnum.morphId && morphFeature == null) {
      debugger(when: kDebugMode);
      throw ("morphFeature is null in PracticeActivityModel");
    }
  }

  PracticeTarget get practiceTarget => PracticeTarget(
        tokens: targetTokens,
        activityType: activityType,
        morphFeature: morphFeature,
      );

  bool onMultipleChoiceSelect(
    ConstructIdentifier choiceConstruct,
    String choice,
  ) {
    if (multipleChoiceContent == null) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        m: "in onMultipleChoiceSelect with null multipleChoiceContent",
        s: StackTrace.current,
        data: toJson(),
      );
      return false;
    }

    if (practiceTarget.isComplete ||
        practiceTarget.record.alreadyHasMatchResponse(
          choiceConstruct,
          choice,
        )) {
      // the user has already selected this choice
      // so we don't want to record it again
      return false;
    }

    final bool isCorrect = multipleChoiceContent!.isCorrect(choice);

    // NOTE: the response is associated with the contructId of the choice, not the selected token
    // example: the user selects the word "cat" to match with the emoji 🐶
    // the response is associated with correct word "dog", not the word "cat"
    practiceTarget.record.addResponse(
      cId: choiceConstruct,
      target: practiceTarget,
      text: choice,
      score: isCorrect ? 1 : 0,
    );

    return isCorrect;
  }

  bool onMatch(
    PangeaToken token,
    PracticeChoice choice,
  ) {
    // the user has already selected this choice
    // so we don't want to record it again
    if (practiceTarget.isComplete ||
        practiceTarget.record.alreadyHasMatchResponse(
          token.vocabConstructID,
          choice.choiceContent,
        )) {
      return false;
    }

    bool isCorrect = false;
    if (multipleChoiceContent != null) {
      isCorrect = multipleChoiceContent!.answers.any(
        (answer) => answer.toLowerCase() == choice.choiceContent.toLowerCase(),
      );
    } else {
      // we check to see if it's in the list of acceptable answers
      // rather than if the vocabForm is the same because an emoji
      // could be in multiple constructs so there could be multiple answers
      final answers = matchContent!.matchInfo[token.vocabForm];
      debugger(when: answers == null && kDebugMode);
      isCorrect = answers!.contains(choice.choiceContent);
    }

    // NOTE: the response is associated with the contructId of the selected token, not the choice
    // example: the user selects the word "cat" to match with the emoji 🐶
    // the response is associated with incorrect word "cat", not the word "dog"
    practiceTarget.record.addResponse(
      cId: token.vocabConstructID,
      target: practiceTarget,
      text: choice.choiceContent,
      score: isCorrect ? 1 : 0,
    );

    return isCorrect;
  }

  factory PracticeActivityModel.fromJson(Map<String, dynamic> json) {
    // moving from multiple_choice to content as the key
    // this is to make the model more generic
    // here for backward compatibility
    final Map<String, dynamic>? contentMap =
        (json['content'] ?? json["multiple_choice"]) as Map<String, dynamic>?;

    if (contentMap == null) {
      Sentry.addBreadcrumb(
        Breadcrumb(data: {"json": json}),
      );
      throw ("content is null in PracticeActivityModel.fromJson");
    }

    if (json['lang_code'] is! String) {
      Sentry.addBreadcrumb(
        Breadcrumb(data: {"json": json}),
      );
      throw ("lang_code is not a string in PracticeActivityModel.fromJson");
    }

    final targetConstructsEntry =
        json['tgt_constructs'] ?? json['target_constructs'];
    if (targetConstructsEntry is! List) {
      Sentry.addBreadcrumb(
        Breadcrumb(data: {"json": json}),
      );
      throw ("tgt_constructs is not a list in PracticeActivityModel.fromJson");
    }

    return PracticeActivityModel(
      langCode: json['lang_code'] as String,
      activityType: ActivityTypeEnum.fromString(json['activity_type']),
      multipleChoiceContent: json['content'] != null
          ? MultipleChoiceActivity.fromJson(contentMap)
          : null,
      targetTokens: (json['target_tokens'] as List)
          .map((e) => PangeaToken.fromJson(e as Map<String, dynamic>))
          .toList(),
      matchContent: json['match_content'] != null
          ? PracticeMatchActivity.fromJson(contentMap)
          : null,
      morphFeature: json['morph_feature'] != null
          ? MorphFeaturesEnumExtension.fromString(
              json['morph_feature'] as String,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lang_code': langCode,
      'activity_type': activityType.name,
      'content': multipleChoiceContent?.toJson(),
      'target_tokens': targetTokens.map((e) => e.toJson()).toList(),
      'match_content': matchContent?.toJson(),
      'morph_feature': morphFeature?.name,
    };
  }

  // override operator == and hashCode
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PracticeActivityModel &&
        const ListEquality().equals(other.targetTokens, targetTokens) &&
        other.langCode == langCode &&
        other.activityType == activityType &&
        other.multipleChoiceContent == multipleChoiceContent &&
        other.matchContent == matchContent &&
        other.morphFeature == morphFeature;
  }

  @override
  int get hashCode {
    return const ListEquality().hash(targetTokens) ^
        langCode.hashCode ^
        activityType.hashCode ^
        multipleChoiceContent.hashCode ^
        matchContent.hashCode ^
        morphFeature.hashCode;
  }
}

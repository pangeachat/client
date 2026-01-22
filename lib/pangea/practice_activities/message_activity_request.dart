import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/choreographer/choreo_record_model.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// includes feedback text and the bad activity model
class ActivityQualityFeedback {
  final String feedbackText;
  final PracticeActivityModel badActivity;

  ActivityQualityFeedback({
    required this.feedbackText,
    required this.badActivity,
  });

  Map<String, dynamic> toJson() {
    return {
      'feedback_text': feedbackText,
      'bad_activity': badActivity.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ActivityQualityFeedback &&
        other.feedbackText == feedbackText &&
        other.badActivity == badActivity;
  }

  @override
  int get hashCode {
    return feedbackText.hashCode ^ badActivity.hashCode;
  }
}

class GrammarErrorRequestInfo {
  final ChoreoRecordModel choreo;
  final int stepIndex;
  final String eventID;
  final PangeaMessageEvent? event;

  const GrammarErrorRequestInfo({
    required this.choreo,
    required this.stepIndex,
    required this.eventID,
    this.event,
  });

  Map<String, dynamic> toJson() {
    return {
      'choreo': choreo.toJson(),
      'step_index': stepIndex,
      'event_id': eventID,
    };
  }

  factory GrammarErrorRequestInfo.fromJson(Map<String, dynamic> json) {
    return GrammarErrorRequestInfo(
      choreo: ChoreoRecordModel.fromJson(json['choreo']),
      stepIndex: json['step_index'] as int,
      eventID: json['event_id'] as String,
    );
  }
}

class MessageActivityRequest {
  final String userL1;
  final String userL2;
  final PracticeTarget target;
  final ActivityQualityFeedback? activityQualityFeedback;
  final GrammarErrorRequestInfo? grammarErrorInfo;

  MessageActivityRequest({
    required this.userL1,
    required this.userL2,
    required this.activityQualityFeedback,
    required this.target,
    this.grammarErrorInfo,
  }) {
    if (target.tokens.isEmpty) {
      throw Exception('Target tokens must not be empty');
    }
  }

  String promptText(BuildContext context) {
    switch (target.activityType) {
      case ActivityTypeEnum.grammarCategory:
        return L10n.of(context).whatIsTheMorphTag(
          target.morphFeature!.getDisplayCopy(context),
          target.tokens.first.text.content,
        );
      case ActivityTypeEnum.grammarError:
        return L10n.of(context).fillInBlank;
      default:
        return target.tokens.first.vocabConstructID.lemma;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'user_l1': userL1,
      'user_l2': userL2,
      'activity_quality_feedback': activityQualityFeedback?.toJson(),
      'target_tokens': target.tokens.map((e) => e.toJson()).toList(),
      'target_type': target.activityType.name,
      'target_morph_feature': target.morphFeature,
      'grammar_error_info': grammarErrorInfo?.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is MessageActivityRequest &&
        other.userL1 == userL1 &&
        other.userL2 == userL2 &&
        other.target == target &&
        other.activityQualityFeedback?.feedbackText ==
            activityQualityFeedback?.feedbackText &&
        other.grammarErrorInfo == grammarErrorInfo;
  }

  @override
  int get hashCode {
    return activityQualityFeedback.hashCode ^
        target.hashCode ^
        userL1.hashCode ^
        userL2.hashCode ^
        grammarErrorInfo.hashCode;
  }
}

class MessageActivityResponse {
  final PracticeActivityModel activity;

  MessageActivityResponse({
    required this.activity,
  });

  factory MessageActivityResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('activity')) {
      Sentry.addBreadcrumb(Breadcrumb(data: {"json": json}));
      throw Exception('Activity not found in message activity response');
    }

    if (json['activity'] is! Map<String, dynamic>) {
      Sentry.addBreadcrumb(Breadcrumb(data: {"json": json}));
      throw Exception('Activity is not a map in message activity response');
    }

    return MessageActivityResponse(
      activity: PracticeActivityModel.fromJson(
        json['activity'] as Map<String, dynamic>,
      ),
    );
  }
}

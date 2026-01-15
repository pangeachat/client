import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';

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

class MessageActivityRequest {
  final String userL1;
  final String userL2;
  final PracticeTarget target;
  final ActivityQualityFeedback? activityQualityFeedback;

  MessageActivityRequest({
    required this.userL1,
    required this.userL2,
    required this.activityQualityFeedback,
    required this.target,
  }) {
    if (target.tokens.isEmpty) {
      throw Exception('Target tokens must not be empty');
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
            activityQualityFeedback?.feedbackText;
  }

  @override
  int get hashCode {
    return activityQualityFeedback.hashCode ^
        target.hashCode ^
        userL1.hashCode ^
        userL2.hashCode;
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

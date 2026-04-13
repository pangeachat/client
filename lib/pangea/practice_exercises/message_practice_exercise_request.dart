import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/choreographer/choreo_record_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_target.dart';

// includes feedback text and the bad exercise model
class PracticeExerciseQualityFeedback {
  final String feedbackText;
  final PracticeExerciseModel badExercise;

  PracticeExerciseQualityFeedback({
    required this.feedbackText,
    required this.badExercise,
  });

  Map<String, dynamic> toJson() {
    return {
      'feedback_text': feedbackText,
      'bad_activity': badExercise.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PracticeExerciseQualityFeedback &&
        other.feedbackText == feedbackText &&
        other.badExercise == badExercise;
  }

  @override
  int get hashCode {
    return feedbackText.hashCode ^ badExercise.hashCode;
  }
}

class GrammarErrorRequestInfo {
  final ChoreoRecordModel choreo;
  final int stepIndex;
  final String eventID;
  final String translation;

  const GrammarErrorRequestInfo({
    required this.choreo,
    required this.stepIndex,
    required this.eventID,
    required this.translation,
  });

  Map<String, dynamic> toJson() {
    return {
      'choreo': choreo.toJson(),
      'step_index': stepIndex,
      'event_id': eventID,
      'translation': translation,
    };
  }

  factory GrammarErrorRequestInfo.fromJson(Map<String, dynamic> json) {
    return GrammarErrorRequestInfo(
      choreo: ChoreoRecordModel.fromJson(json['choreo']),
      stepIndex: json['step_index'] as int,
      eventID: json['event_id'] as String,
      translation: json['translation'] as String,
    );
  }
}

class MessagePracticeExerciseRequest {
  final String userL1;
  final String userL2;
  final PracticeTarget target;
  final PracticeExerciseQualityFeedback? exerciseQualityFeedback;
  final GrammarErrorRequestInfo? grammarErrorInfo;
  final ExampleMessageInfo? exampleMessage;
  final AudioExampleMessage? audioExampleMessage;

  MessagePracticeExerciseRequest({
    required this.userL1,
    required this.userL2,
    required this.exerciseQualityFeedback,
    required this.target,
    this.grammarErrorInfo,
    this.exampleMessage,
    this.audioExampleMessage,
  }) {
    if (target.tokens.isEmpty) {
      throw Exception('Target tokens must not be empty');
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'user_l1': userL1,
      'user_l2': userL2,
      'activity_quality_feedback': exerciseQualityFeedback?.toJson(),
      'target_tokens': target.tokens.map((e) => e.toJson()).toList(),
      'target_type': target.exerciseType.name,
      'target_morph_feature': target.morphFeature,
      'grammar_error_info': grammarErrorInfo?.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is MessagePracticeExerciseRequest &&
        other.userL1 == userL1 &&
        other.userL2 == userL2 &&
        other.target == target &&
        other.exerciseQualityFeedback?.feedbackText ==
            exerciseQualityFeedback?.feedbackText &&
        other.grammarErrorInfo == grammarErrorInfo;
  }

  @override
  int get hashCode {
    return exerciseQualityFeedback.hashCode ^
        target.hashCode ^
        userL1.hashCode ^
        userL2.hashCode ^
        grammarErrorInfo.hashCode;
  }
}

class MessagePracticeExerciseResponse {
  final PracticeExerciseModel exercise;

  MessagePracticeExerciseResponse({required this.exercise});

  factory MessagePracticeExerciseResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('activity')) {
      Sentry.addBreadcrumb(Breadcrumb(data: {"json": json}));
      throw Exception('Exercise not found in message exercise response');
    }

    if (json['activity'] is! Map<String, dynamic>) {
      Sentry.addBreadcrumb(Breadcrumb(data: {"json": json}));
      throw Exception('Exercise is not a map in message exercise response');
    }

    return MessagePracticeExerciseResponse(
      exercise: PracticeExerciseModel.fromJson(
        json['activity'] as Map<String, dynamic>,
      ),
    );
  }
}

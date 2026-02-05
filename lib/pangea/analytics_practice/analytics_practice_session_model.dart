import 'package:flutter/painting.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_constants.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';

class MorphExampleInfo {
  final List<InlineSpan> exampleMessage;

  const MorphExampleInfo({required this.exampleMessage});

  Map<String, dynamic> toJson() {
    final segments = <Map<String, dynamic>>[];

    for (final span in exampleMessage) {
      if (span is TextSpan) {
        segments.add({
          'text': span.text ?? '',
          'isBold': span.style?.fontWeight == FontWeight.bold,
        });
      }
    }

    return {'segments': segments};
  }

  factory MorphExampleInfo.fromJson(Map<String, dynamic> json) {
    final segments = json['segments'] as List<dynamic>? ?? [];

    final spans = <InlineSpan>[];
    for (final segment in segments) {
      final text = segment['text'] as String? ?? '';
      final isBold = segment['isBold'] as bool? ?? false;

      spans.add(
        TextSpan(
          text: text,
          style: isBold ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
      );
    }

    return MorphExampleInfo(exampleMessage: spans);
  }
}

class AnalyticsActivityTarget {
  final PracticeTarget target;
  final GrammarErrorRequestInfo? grammarErrorInfo;
  final MorphExampleInfo? morphExampleInfo;

  AnalyticsActivityTarget({
    required this.target,
    this.grammarErrorInfo,
    this.morphExampleInfo,
  });

  Map<String, dynamic> toJson() => {
    'target': target.toJson(),
    'grammarErrorInfo': grammarErrorInfo?.toJson(),
    'morphExampleInfo': morphExampleInfo?.toJson(),
  };

  factory AnalyticsActivityTarget.fromJson(Map<String, dynamic> json) =>
      AnalyticsActivityTarget(
        target: PracticeTarget.fromJson(json['target']),
        grammarErrorInfo: json['grammarErrorInfo'] != null
            ? GrammarErrorRequestInfo.fromJson(json['grammarErrorInfo'])
            : null,
        morphExampleInfo: json['morphExampleInfo'] != null
            ? MorphExampleInfo.fromJson(json['morphExampleInfo'])
            : null,
      );
}

class AnalyticsPracticeSessionModel {
  final DateTime startedAt;
  final List<AnalyticsActivityTarget> practiceTargets;
  final String userL1;
  final String userL2;

  AnalyticsPracticeSessionState state;

  AnalyticsPracticeSessionModel({
    required this.startedAt,
    required this.practiceTargets,
    required this.userL1,
    required this.userL2,
    AnalyticsPracticeSessionState? state,
  }) : state = state ?? const AnalyticsPracticeSessionState();

  // Maximum activities to attempt (including skips)
  int get _maxAttempts =>
      (AnalyticsPracticeConstants.practiceGroupSize +
              AnalyticsPracticeConstants.errorBufferSize)
          .clamp(0, practiceTargets.length)
          .toInt();

  int get _completionGoal => AnalyticsPracticeConstants.practiceGroupSize.clamp(
    0,
    practiceTargets.length,
  );

  // Total attempted so far (completed + skipped)
  int get _totalAttempted => state.currentIndex + state.skippedActivities;

  bool get isComplete {
    final complete =
        state.finished ||
        state.currentIndex >= _completionGoal ||
        _totalAttempted >= _maxAttempts;
    return complete;
  }

  double get progress {
    final possibleCompletions =
        (state.currentIndex + _maxAttempts - _totalAttempted).clamp(
          0,
          _completionGoal,
        );
    return possibleCompletions > 0
        ? (state.currentIndex / possibleCompletions).clamp(0.0, 1.0)
        : 1.0;
  }

  List<MessageActivityRequest> get activityRequests {
    return practiceTargets.map((target) {
      return MessageActivityRequest(
        userL1: userL1,
        userL2: userL2,
        activityQualityFeedback: null,
        target: target.target,
        grammarErrorInfo: target.grammarErrorInfo,
        morphExampleInfo: target.morphExampleInfo,
      );
    }).toList();
  }

  void setElapsedSeconds(int seconds) =>
      state = state.copyWith(elapsedSeconds: seconds);

  void finishSession() => state = state.copyWith(finished: true);

  void completeActivity() =>
      state = state.copyWith(currentIndex: state.currentIndex + 1);

  void incrementSkippedActivities() =>
      state = state.copyWith(skippedActivities: state.skippedActivities + 1);

  void submitAnswer(OneConstructUse use) =>
      state = state.copyWith(completedUses: [...state.completedUses, use]);

  factory AnalyticsPracticeSessionModel.fromJson(Map<String, dynamic> json) {
    return AnalyticsPracticeSessionModel(
      startedAt: DateTime.parse(json['startedAt'] as String),
      practiceTargets: (json['practiceTargets'] as List<dynamic>)
          .map((e) => AnalyticsActivityTarget.fromJson(e))
          .whereType<AnalyticsActivityTarget>()
          .toList(),
      userL1: json['userL1'] as String,
      userL2: json['userL2'] as String,
      state: AnalyticsPracticeSessionState.fromJson(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startedAt': startedAt.toIso8601String(),
      'practiceTargets': practiceTargets.map((e) => e.toJson()).toList(),
      'userL1': userL1,
      'userL2': userL2,
      ...state.toJson(),
    };
  }
}

class AnalyticsPracticeSessionState {
  final List<OneConstructUse> completedUses;
  final int currentIndex;
  final bool finished;
  final int elapsedSeconds;
  final int skippedActivities;

  const AnalyticsPracticeSessionState({
    this.completedUses = const [],
    this.currentIndex = 0,
    this.finished = false,
    this.elapsedSeconds = 0,
    this.skippedActivities = 0,
  });

  int get totalXpGained => completedUses.fold(0, (sum, use) => sum + use.xp);

  double get accuracy {
    if (completedUses.isEmpty) return 0.0;
    final correct = completedUses.where((use) => use.xp > 0).length;
    final result = correct / completedUses.length;
    return (result * 100).truncateToDouble();
  }

  bool get _giveAccuracyBonus => accuracy >= 100.0;

  bool get _giveTimeBonus =>
      elapsedSeconds <= AnalyticsPracticeConstants.timeForBonus;

  int get bonusXP => accuracyBonusXP + timeBonusXP;

  int get accuracyBonusXP => _giveAccuracyBonus ? _bonusXP : 0;

  int get timeBonusXP => _giveTimeBonus ? _bonusXP : 0;

  int get _bonusXP => _bonusUses.fold(0, (sum, use) => sum + use.xp);

  int get allXPGained => totalXpGained + bonusXP;

  List<OneConstructUse> get _bonusUses =>
      completedUses.where((use) => use.xp > 0).map(_bonusUse).toList();

  List<OneConstructUse> get allBonusUses => [
    if (_giveAccuracyBonus) ..._bonusUses,
    if (_giveTimeBonus) ..._bonusUses,
  ];

  OneConstructUse _bonusUse(OneConstructUse originalUse) => OneConstructUse(
    useType: ConstructUseTypeEnum.bonus,
    constructType: originalUse.constructType,
    metadata: ConstructUseMetaData(
      roomId: originalUse.metadata.roomId,
      timeStamp: DateTime.now(),
    ),
    category: originalUse.category,
    lemma: originalUse.lemma,
    form: originalUse.form,
    xp: ConstructUseTypeEnum.bonus.pointValue,
  );

  AnalyticsPracticeSessionState copyWith({
    List<OneConstructUse>? completedUses,
    int? currentIndex,
    bool? finished,
    int? elapsedSeconds,
    int? skippedActivities,
  }) {
    return AnalyticsPracticeSessionState(
      completedUses: completedUses ?? this.completedUses,
      currentIndex: currentIndex ?? this.currentIndex,
      finished: finished ?? this.finished,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      skippedActivities: skippedActivities ?? this.skippedActivities,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completedUses': completedUses.map((e) => e.toJson()).toList(),
      'currentIndex': currentIndex,
      'finished': finished,
      'elapsedSeconds': elapsedSeconds,
      'skippedActivities': skippedActivities,
    };
  }

  factory AnalyticsPracticeSessionState.fromJson(Map<String, dynamic> json) {
    return AnalyticsPracticeSessionState(
      completedUses:
          (json['completedUses'] as List<dynamic>?)
              ?.map((e) => OneConstructUse.fromJson(e))
              .whereType<OneConstructUse>()
              .toList() ??
          [],
      currentIndex: json['currentIndex'] as int? ?? 0,
      finished: json['finished'] as bool? ?? false,
      elapsedSeconds: json['elapsedSeconds'] as int? ?? 0,
      skippedActivities: json['skippedActivities'] as int? ?? 0,
    );
  }
}

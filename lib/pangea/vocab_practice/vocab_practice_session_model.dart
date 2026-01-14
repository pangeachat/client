import 'dart:math';

import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_constants.dart';

class VocabPracticeSessionModel {
  final DateTime startedAt;
  final List<PracticeTarget> practiceTargets;
  final String userL1;
  final String userL2;

  VocabPracticeSessionState state;

  VocabPracticeSessionModel({
    required this.startedAt,
    required this.practiceTargets,
    required this.userL1,
    required this.userL2,
    VocabPracticeSessionState? state,
  })  : assert(
          practiceTargets.every(
            (t) => {ActivityTypeEnum.lemmaMeaning, ActivityTypeEnum.lemmaAudio}
                .contains(t.activityType),
          ),
        ),
        assert(
          practiceTargets.length == VocabPracticeConstants.practiceGroupSize,
        ),
        state = state ?? const VocabPracticeSessionState();

  int get _availableActivities => min(
        VocabPracticeConstants.practiceGroupSize,
        practiceTargets.length,
      );

  bool get isComplete => state.currentIndex >= _availableActivities;

  double get progress =>
      (state.currentIndex / _availableActivities).clamp(0.0, 1.0);

  List<MessageActivityRequest> get activityRequests {
    return practiceTargets.map((target) {
      return MessageActivityRequest(
        userL1: userL1,
        userL2: userL2,
        activityQualityFeedback: null,
        targetTokens: target.tokens,
        targetType: target.activityType,
        targetMorphFeature: null,
      );
    }).toList();
  }

  void setElapsedSeconds(int seconds) =>
      state = state.copyWith(elapsedSeconds: seconds);

  void finishSession() => state = state.copyWith(finished: true);

  void completeActivity() =>
      state = state.copyWith(currentIndex: state.currentIndex + 1);

  void submitAnswer(OneConstructUse use) => state = state.copyWith(
        completedUses: [...state.completedUses, use],
      );

  factory VocabPracticeSessionModel.fromJson(Map<String, dynamic> json) {
    return VocabPracticeSessionModel(
      startedAt: DateTime.parse(json['startedAt'] as String),
      practiceTargets: (json['practiceTargets'] as List<dynamic>)
          .map((e) => PracticeTarget.fromJson(e))
          .whereType<PracticeTarget>()
          .toList(),
      userL1: json['userL1'] as String,
      userL2: json['userL2'] as String,
      state: VocabPracticeSessionState.fromJson(
        json,
      ),
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

class VocabPracticeSessionState {
  final List<OneConstructUse> completedUses;
  final int currentIndex;
  final bool finished;
  final int elapsedSeconds;

  const VocabPracticeSessionState({
    this.completedUses = const [],
    this.currentIndex = 0,
    this.finished = false,
    this.elapsedSeconds = 0,
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
      elapsedSeconds <= VocabPracticeConstants.timeForBonus;

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

  VocabPracticeSessionState copyWith({
    List<OneConstructUse>? completedUses,
    int? currentIndex,
    bool? finished,
    int? elapsedSeconds,
  }) {
    return VocabPracticeSessionState(
      completedUses: completedUses ?? this.completedUses,
      currentIndex: currentIndex ?? this.currentIndex,
      finished: finished ?? this.finished,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completedUses': completedUses.map((e) => e.toJson()).toList(),
      'currentIndex': currentIndex,
      'finished': finished,
      'elapsedSeconds': elapsedSeconds,
    };
  }

  factory VocabPracticeSessionState.fromJson(Map<String, dynamic> json) {
    return VocabPracticeSessionState(
      completedUses: (json['completedUses'] as List<dynamic>?)
              ?.map((e) => OneConstructUse.fromJson(e))
              .whereType<OneConstructUse>()
              .toList() ??
          [],
      currentIndex: json['currentIndex'] as int,
      finished: json['finished'] as bool,
      elapsedSeconds: json['elapsedSeconds'] as int,
    );
  }
}

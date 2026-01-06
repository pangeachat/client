import 'dart:math';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class VocabPracticeSessionModel {
  final DateTime startedAt;
  final List<ConstructIdentifier> sortedConstructIds;
  final List<ActivityTypeEnum> activityTypes;
  final String userL1;
  final String userL2;

  int currentIndex;
  int currentGroup;

  final List<OneConstructUse> completedUses;
  bool finished;
  int elapsedSeconds;

  VocabPracticeSessionModel({
    required this.startedAt,
    required this.sortedConstructIds,
    required this.activityTypes,
    required this.userL1,
    required this.userL2,
    required this.completedUses,
    this.currentIndex = 0,
    this.currentGroup = 0,
    this.finished = false,
    this.elapsedSeconds = 0,
  })  : assert(
          activityTypes.every(
            (t) => {ActivityTypeEnum.lemmaMeaning, ActivityTypeEnum.lemmaAudio}
                .contains(t),
          ),
        ),
        assert(
          activityTypes.length == practiceGroupSize,
        );

  static const int practiceGroupSize = 10;

  int get currentAvailableActivities => min(
        ((currentGroup + 1) * practiceGroupSize),
        sortedConstructIds.length,
      );

  bool get hasCompletedCurrentGroup =>
      currentIndex >= currentAvailableActivities;

  int get timeForBonus => 60;

  double get progress =>
      (currentIndex / currentAvailableActivities).clamp(0.0, 1.0);

  List<ConstructIdentifier> get currentPracticeGroup => sortedConstructIds
      .skip(currentGroup * practiceGroupSize)
      .take(practiceGroupSize)
      .toList();

  ConstructIdentifier? get currentConstructId {
    if (currentIndex < 0 || hasCompletedCurrentGroup) {
      return null;
    }
    return currentPracticeGroup[currentIndex % practiceGroupSize];
  }

  ActivityTypeEnum? get currentActivityType {
    if (currentIndex < 0 || hasCompletedCurrentGroup) {
      return null;
    }
    return activityTypes[currentIndex % practiceGroupSize];
  }

  MessageActivityRequest? get currentActivityRequest {
    final constructId = currentConstructId;
    if (constructId == null || currentActivityType == null) return null;

    final activityType = currentActivityType;
    return MessageActivityRequest(
      userL1: userL1,
      userL2: userL2,
      activityQualityFeedback: null,
      targetTokens: [
        PangeaToken(
          lemma: Lemma(
            text: constructId.lemma,
            saveVocab: true,
            form: constructId.lemma,
          ),
          pos: constructId.category,
          text: PangeaTokenText.fromString(constructId.lemma),
          morph: {},
        ),
      ],
      targetType: activityType!,
      targetMorphFeature: null,
    );
  }

  int get totalXpGained => completedUses.fold(0, (sum, use) => sum + use.xp);

  double get accuracy {
    if (completedUses.isEmpty) return 0.0;
    final correct = completedUses.where((use) => use.xp > 0).length;
    final result = correct / completedUses.length;
    return (result * 100).truncateToDouble();
  }

  void finishSession() {
    finished = true;

    // give bonus XP uses for each construct if earned
    if (accuracy >= 100) {
      final bonusUses = completedUses
          .where((use) => use.xp > 0)
          .map(
            (use) => OneConstructUse(
              useType: ConstructUseTypeEnum.bonus,
              constructType: use.constructType,
              metadata: ConstructUseMetaData(
                roomId: use.metadata.roomId,
                timeStamp: DateTime.now(),
              ),
              category: use.category,
              lemma: use.lemma,
              form: use.form,
              xp: ConstructUseTypeEnum.bonus.pointValue,
            ),
          )
          .toList();

      MatrixState
          .pangeaController.matrixState.analyticsDataService.updateService
          .addAnalytics(
        null,
        bonusUses,
      );
    }

    if (elapsedSeconds <= timeForBonus) {
      final bonusUses = completedUses
          .where((use) => use.xp > 0)
          .map(
            (use) => OneConstructUse(
              useType: ConstructUseTypeEnum.bonus,
              constructType: use.constructType,
              metadata: ConstructUseMetaData(
                roomId: use.metadata.roomId,
                timeStamp: DateTime.now(),
              ),
              category: use.category,
              lemma: use.lemma,
              form: use.form,
              xp: ConstructUseTypeEnum.bonus.pointValue,
            ),
          )
          .toList();

      MatrixState
          .pangeaController.matrixState.analyticsDataService.updateService
          .addAnalytics(
        null,
        bonusUses,
      );
    }
  }

  void submitAnswer(PracticeActivityModel activity, bool isCorrect) {
    final useType = isCorrect
        ? activity.activityType.correctUse
        : activity.activityType.incorrectUse;

    final use = OneConstructUse(
      useType: useType,
      constructType: ConstructTypeEnum.vocab,
      metadata: ConstructUseMetaData(
        roomId: null,
        timeStamp: DateTime.now(),
      ),
      category: activity.targetTokens.first.pos,
      lemma: activity.targetTokens.first.lemma.text,
      form: activity.targetTokens.first.lemma.text,
      xp: useType.pointValue,
    );

    completedUses.add(use);

    // Give XP immediately
    MatrixState.pangeaController.matrixState.analyticsDataService.updateService
        .addAnalytics(
      null,
      [use],
    );
  }

  void completeActivity(PracticeActivityModel activity) {
    currentIndex += 1;
  }

  factory VocabPracticeSessionModel.fromJson(Map<String, dynamic> json) {
    return VocabPracticeSessionModel(
      startedAt: DateTime.parse(json['startedAt'] as String),
      sortedConstructIds: (json['sortedConstructIds'] as List<dynamic>)
          .map((e) => ConstructIdentifier.fromJson(e))
          .whereType<ConstructIdentifier>()
          .toList(),
      activityTypes: (json['activityTypes'] as List<dynamic>)
          .map(
            (e) => ActivityTypeEnum.values.firstWhere(
              (at) => at.name == (e as String),
            ),
          )
          .whereType<ActivityTypeEnum>()
          .toList(),
      userL1: json['userL1'] as String,
      userL2: json['userL2'] as String,
      currentIndex: json['currentIndex'] as int,
      currentGroup: json['currentGroup'] as int,
      completedUses: (json['completedUses'] as List<dynamic>?)
              ?.map((e) => OneConstructUse.fromJson(e))
              .whereType<OneConstructUse>()
              .toList() ??
          [],
      finished: json['finished'] as bool? ?? false,
      elapsedSeconds: json['elapsedSeconds'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startedAt': startedAt.toIso8601String(),
      'sortedConstructIds': sortedConstructIds.map((e) => e.toJson()).toList(),
      'activityTypes': activityTypes.map((e) => e.name).toList(),
      'userL1': userL1,
      'userL2': userL2,
      'currentIndex': currentIndex,
      'currentGroup': currentGroup,
      'completedUses': completedUses.map((e) => e.toJson()).toList(),
      'finished': finished,
      'elapsedSeconds': elapsedSeconds,
    };
  }
}

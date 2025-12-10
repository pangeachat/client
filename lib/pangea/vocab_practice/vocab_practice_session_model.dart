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

  int currentIndex;
  int currentGroup;

  final List<OneConstructUse> completedUses;
  bool finished;

  VocabPracticeSessionModel({
    required this.startedAt,
    required this.sortedConstructIds,
    required this.activityTypes,
    required this.completedUses,
    this.currentIndex = 0,
    this.currentGroup = 0,
    this.finished = false,
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

  bool get isFinshed => finished || currentIndex >= sortedConstructIds.length;

  bool get hasCompletedCurrentGroup =>
      currentIndex >= ((currentGroup + 1) * practiceGroupSize);

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
      userL1: MatrixState.pangeaController.userController.userL1!.langCode,
      userL2: MatrixState.pangeaController.userController.userL2!.langCode,
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

  void finishSession() => finished = true;

  void completeActivity(PracticeActivityModel activity) {
    currentIndex += 1;
    completedUses.addAll(
      activity.practiceTarget.record.responses.map(
        (r) {
          final useType = r.isCorrect
              ? activity.activityType.correctUse
              : activity.activityType.incorrectUse;

          return OneConstructUse(
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
        },
      ),
    );
  }

  void incrementGroup() {
    currentGroup += 1;
    currentIndex = max(currentIndex, currentGroup * practiceGroupSize);

    activityTypes.clear();
    final r = Random();
    final activityTypeOptions = [
      ActivityTypeEnum.lemmaMeaning,
      ActivityTypeEnum.lemmaAudio,
    ];
    activityTypes.addAll(
      List.generate(
        practiceGroupSize,
        (_) => activityTypeOptions[r.nextInt(activityTypeOptions.length)],
      ),
    );
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
      currentIndex: json['currentIndex'] as int,
      currentGroup: json['currentGroup'] as int,
      completedUses: (json['completedUses'] as List<dynamic>?)
              ?.map((e) => OneConstructUse.fromJson(e))
              .whereType<OneConstructUse>()
              .toList() ??
          [],
      finished: json['finished'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startedAt': startedAt.toIso8601String(),
      'sortedConstructIds': sortedConstructIds.map((e) => e.toJson()).toList(),
      'activityTypes': activityTypes.map((e) => e.name).toList(),
      'currentIndex': currentIndex,
      'currentGroup': currentGroup,
      'completedUses': completedUses.map((e) => e.toJson()).toList(),
      'finished': finished,
    };
  }
}

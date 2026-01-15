import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_choice.dart';
import 'package:fluffychat/pangea/practice_activities/practice_match.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';

sealed class PracticeActivityModel {
  final List<PangeaToken> targetTokens;
  final ActivityTypeEnum activityType;
  final String langCode;

  const PracticeActivityModel({
    required this.targetTokens,
    required this.langCode,
    required this.activityType,
  });

  PracticeTarget get practiceTarget => PracticeTarget(
        tokens: targetTokens,
        activityType: activityType,
      );

  factory PracticeActivityModel.fromJson(Map<String, dynamic> json) {
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

    final type = ActivityTypeEnum.fromString(json['activity_type']);

    final morph = json['morph_feature'] != null
        ? MorphFeaturesEnumExtension.fromString(
            json['morph_feature'] as String,
          )
        : null;

    final tokens = (json['target_tokens'] as List)
        .map((e) => PangeaToken.fromJson(e as Map<String, dynamic>))
        .toList();

    final langCode = json['lang_code'] as String;

    final multipleChoiceContent = json['content'] != null
        ? MultipleChoiceActivity.fromJson(
            json['content'] as Map<String, dynamic>,
          )
        : null;

    final matchContent = json['match_content'] != null
        ? PracticeMatchActivity.fromJson(
            json['match_content'] as Map<String, dynamic>,
          )
        : null;

    switch (type) {
      case ActivityTypeEnum.grammarCategory:
        assert(
          morph != null,
          "morphFeature is null in PracticeActivityModel.fromJson for grammarCategory",
        );
        assert(
          multipleChoiceContent != null,
          "multipleChoiceContent is null in PracticeActivityModel.fromJson for grammarCategory",
        );
        return MorphCategoryPracticeActivityModel(
          langCode: langCode,
          targetTokens: tokens,
          morphFeature: morph!,
          multipleChoiceContent: multipleChoiceContent!,
        );
      case ActivityTypeEnum.lemmaAudio:
        assert(
          multipleChoiceContent != null,
          "multipleChoiceContent is null in PracticeActivityModel.fromJson for lemmaAudio",
        );
        return VocabAudioPracticeActivityModel(
          langCode: langCode,
          targetTokens: tokens,
          multipleChoiceContent: multipleChoiceContent!,
        );
      case ActivityTypeEnum.lemmaMeaning:
        assert(
          multipleChoiceContent != null,
          "multipleChoiceContent is null in PracticeActivityModel.fromJson for lemmaMeaning",
        );
        return VocabMeaningPracticeActivityModel(
          langCode: langCode,
          targetTokens: tokens,
          multipleChoiceContent: multipleChoiceContent!,
        );
      case ActivityTypeEnum.emoji:
        assert(
          matchContent != null,
          "matchContent is null in PracticeActivityModel.fromJson for emoji",
        );
        return EmojiPracticeActivityModel(
          langCode: langCode,
          targetTokens: tokens,
          matchContent: matchContent!,
        );
      case ActivityTypeEnum.lemmaId:
        assert(
          multipleChoiceContent != null,
          "multipleChoiceContent is null in PracticeActivityModel.fromJson for lemmaId",
        );
        return LemmaPracticeActivityModel(
          langCode: langCode,
          targetTokens: tokens,
          multipleChoiceContent: multipleChoiceContent!,
        );
      case ActivityTypeEnum.wordMeaning:
        assert(
          matchContent != null,
          "matchContent is null in PracticeActivityModel.fromJson for wordMeaning",
        );
        return LemmaMeaningPracticeActivityModel(
          langCode: langCode,
          targetTokens: tokens,
          matchContent: matchContent!,
        );
      case ActivityTypeEnum.morphId:
        assert(
          morph != null,
          "morphFeature is null in PracticeActivityModel.fromJson for morphId",
        );
        assert(
          multipleChoiceContent != null,
          "multipleChoiceContent is null in PracticeActivityModel.fromJson for morphId",
        );
        return MorphMatchPracticeActivityModel(
          langCode: langCode,
          targetTokens: tokens,
          morphFeature: morph!,
          multipleChoiceContent: multipleChoiceContent!,
        );
      case ActivityTypeEnum.wordFocusListening:
        assert(
          matchContent != null,
          "matchContent is null in PracticeActivityModel.fromJson for wordFocusListening",
        );
        return WordListeningPracticeActivityModel(
          langCode: langCode,
          targetTokens: tokens,
          matchContent: matchContent!,
        );
      default:
        throw ("Unsupported activity type in PracticeActivityModel.fromJson: $type");
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'lang_code': langCode,
      'activity_type': activityType.name,
      'target_tokens': targetTokens.map((e) => e.toJson()).toList(),
    };
  }
}

sealed class MultipleChoicePracticeActivityModel extends PracticeActivityModel {
  final MultipleChoiceActivity multipleChoiceContent;

  MultipleChoicePracticeActivityModel({
    required super.targetTokens,
    required super.langCode,
    required super.activityType,
    required this.multipleChoiceContent,
  });

  bool onMultipleChoiceSelect(
    ConstructIdentifier choiceConstruct,
    String choice,
  ) {
    if (practiceTarget.isComplete ||
        practiceTarget.record.alreadyHasMatchResponse(
          choiceConstruct,
          choice,
        )) {
      // the user has already selected this choice
      // so we don't want to record it again
      return false;
    }

    final bool isCorrect = multipleChoiceContent.isCorrect(choice);
    practiceTarget.record.addResponse(
      cId: choiceConstruct,
      target: practiceTarget,
      text: choice,
      score: isCorrect ? 1 : 0,
    );
    return isCorrect;
  }

  OneConstructUse constructUse(String choiceContent) {
    final correct = multipleChoiceContent.isCorrect(choiceContent);
    final useType =
        correct ? activityType.correctUse : activityType.incorrectUse;

    return OneConstructUse(
      useType: useType,
      constructType: ConstructTypeEnum.vocab,
      metadata: ConstructUseMetaData(
        roomId: null,
        timeStamp: DateTime.now(),
      ),
      category: targetTokens.first.pos,
      lemma: targetTokens.first.lemma.text,
      form: targetTokens.first.lemma.text,
      xp: useType.pointValue,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['content'] = multipleChoiceContent.toJson();
    return json;
  }
}

sealed class MatchPracticeActivityModel extends PracticeActivityModel {
  final PracticeMatchActivity matchContent;

  MatchPracticeActivityModel({
    required super.targetTokens,
    required super.langCode,
    required super.activityType,
    required this.matchContent,
  });

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

    final answers = matchContent.matchInfo[token.vocabForm];
    final isCorrect = answers!.contains(choice.choiceContent);
    practiceTarget.record.addResponse(
      cId: token.vocabConstructID,
      target: practiceTarget,
      text: choice.choiceContent,
      score: isCorrect ? 1 : 0,
    );

    return isCorrect;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['match_content'] = matchContent.toJson();
    return json;
  }
}

sealed class MorphPracticeActivityModel
    extends MultipleChoicePracticeActivityModel {
  final MorphFeaturesEnum morphFeature;

  MorphPracticeActivityModel({
    required super.targetTokens,
    required super.langCode,
    required super.activityType,
    required super.multipleChoiceContent,
    required this.morphFeature,
  });

  @override
  PracticeTarget get practiceTarget => PracticeTarget(
        tokens: targetTokens,
        activityType: activityType,
        morphFeature: morphFeature,
      );

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['morph_feature'] = morphFeature.name;
    return json;
  }
}

class MorphCategoryPracticeActivityModel extends MorphPracticeActivityModel {
  MorphCategoryPracticeActivityModel({
    required super.targetTokens,
    required super.langCode,
    required super.morphFeature,
    required super.multipleChoiceContent,
  }) : super(
          activityType: ActivityTypeEnum.grammarCategory,
        );

  @override
  OneConstructUse constructUse(String choiceContent) {
    final correct = multipleChoiceContent.isCorrect(choiceContent);
    final useType =
        correct ? activityType.correctUse : activityType.incorrectUse;
    final tag = targetTokens.first.getMorphTag(morphFeature)!;

    return OneConstructUse(
      useType: useType,
      constructType: ConstructTypeEnum.morph,
      metadata: ConstructUseMetaData(
        roomId: null,
        timeStamp: DateTime.now(),
      ),
      category: morphFeature.name,
      lemma: tag,
      form: targetTokens.first.lemma.form,
      xp: useType.pointValue,
    );
  }
}

class MorphMatchPracticeActivityModel extends MorphPracticeActivityModel {
  MorphMatchPracticeActivityModel({
    required super.targetTokens,
    required super.langCode,
    required super.morphFeature,
    required super.multipleChoiceContent,
  }) : super(
          activityType: ActivityTypeEnum.morphId,
        );
}

class VocabAudioPracticeActivityModel
    extends MultipleChoicePracticeActivityModel {
  VocabAudioPracticeActivityModel({
    required super.targetTokens,
    required super.langCode,
    required super.multipleChoiceContent,
  }) : super(
          activityType: ActivityTypeEnum.lemmaAudio,
        );
}

class VocabMeaningPracticeActivityModel
    extends MultipleChoicePracticeActivityModel {
  VocabMeaningPracticeActivityModel({
    required super.targetTokens,
    required super.langCode,
    required super.multipleChoiceContent,
  }) : super(
          activityType: ActivityTypeEnum.lemmaMeaning,
        );
}

class LemmaPracticeActivityModel extends MultipleChoicePracticeActivityModel {
  LemmaPracticeActivityModel({
    required super.targetTokens,
    required super.langCode,
    required super.multipleChoiceContent,
  }) : super(
          activityType: ActivityTypeEnum.lemmaId,
        );
}

class EmojiPracticeActivityModel extends MatchPracticeActivityModel {
  EmojiPracticeActivityModel({
    required super.targetTokens,
    required super.langCode,
    required super.matchContent,
  }) : super(
          activityType: ActivityTypeEnum.emoji,
        );
}

class LemmaMeaningPracticeActivityModel extends MatchPracticeActivityModel {
  LemmaMeaningPracticeActivityModel({
    required super.targetTokens,
    required super.langCode,
    required super.matchContent,
  }) : super(
          activityType: ActivityTypeEnum.wordMeaning,
        );
}

class WordListeningPracticeActivityModel extends MatchPracticeActivityModel {
  WordListeningPracticeActivityModel({
    required super.targetTokens,
    required super.langCode,
    required super.matchContent,
  }) : super(
          activityType: ActivityTypeEnum.wordFocusListening,
        );
}

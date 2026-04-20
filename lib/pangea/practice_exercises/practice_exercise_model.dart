import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_exercises/match_practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/multiple_choice_practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_target.dart';

sealed class PracticeExerciseModel {
  final List<PangeaToken> tokens;
  final String langCode;

  const PracticeExerciseModel({required this.tokens, required this.langCode});

  String get storageKey =>
      '${exerciseType.name}-${tokens.map((e) => e.text.content).join("-")}';

  PracticeTarget get practiceTarget => PracticeTarget(
    exerciseType: exerciseType,
    tokens: tokens,
    morphFeature: this is MorphPracticeExerciseModel
        ? (this as MorphPracticeExerciseModel).morphFeature
        : null,
  );

  bool isCorrect(String choice, PangeaToken token) => false;

  PracticeExerciseTypeEnum get exerciseType {
    switch (this) {
      case MorphCategoryPracticeExerciseModel():
        return PracticeExerciseTypeEnum.grammarCategory;
      case VocabAudioPracticeExerciseModel():
        return PracticeExerciseTypeEnum.lemmaAudio;
      case VocabMeaningPracticeExerciseModel():
        return PracticeExerciseTypeEnum.lemmaMeaning;
      case EmojiPracticeExerciseModel():
        return PracticeExerciseTypeEnum.emoji;
      case LemmaPracticeExerciseModel():
        return PracticeExerciseTypeEnum.lemmaId;
      case LemmaMeaningPracticeExerciseModel():
        return PracticeExerciseTypeEnum.wordMeaning;
      case MorphMatchPracticeExerciseModel():
        return PracticeExerciseTypeEnum.morphId;
      case WordListeningPracticeExerciseModel():
        return PracticeExerciseTypeEnum.wordFocusListening;
      case GrammarErrorPracticeExerciseModel():
        return PracticeExerciseTypeEnum.grammarError;
    }
  }

  factory PracticeExerciseModel.fromJson(Map<String, dynamic> json) {
    if (json[ModelKey.langCode] is! String) {
      Sentry.addBreadcrumb(Breadcrumb(data: {"json": json}));
      throw ("lang_code is not a string in PracticeExerciseModel.fromJson");
    }

    final targetConstructsEntry =
        json['tgt_constructs'] ?? json['target_constructs'];
    if (targetConstructsEntry is! List) {
      Sentry.addBreadcrumb(Breadcrumb(data: {"json": json}));
      throw ("tgt_constructs is not a list in PracticeExerciseModel.fromJson");
    }

    final type = PracticeExerciseTypeEnum.fromString(json['activity_type']);

    final morph = json['morph_feature'] != null
        ? MorphFeaturesEnumExtension.fromString(json['morph_feature'] as String)
        : null;

    final tokens = (json['target_tokens'] as List)
        .map((e) => PangeaToken.fromJson(e as Map<String, dynamic>))
        .toList();

    final langCode = json[ModelKey.langCode] as String;

    final multipleChoiceContent = json['content'] != null
        ? MultipleChoicePracticeExercise.fromJson(
            json['content'] as Map<String, dynamic>,
          )
        : null;

    final matchContent = json['match_content'] != null
        ? MatchPracticeExercise.fromJson(
            json['match_content'] as Map<String, dynamic>,
          )
        : null;

    switch (type) {
      case PracticeExerciseTypeEnum.grammarCategory:
        assert(
          morph != null,
          "morphFeature is null in PracticeExerciseModel.fromJson for grammarCategory",
        );
        assert(
          multipleChoiceContent != null,
          "multipleChoiceContent is null in PracticeExerciseModel.fromJson for grammarCategory",
        );
        return MorphCategoryPracticeExerciseModel(
          langCode: langCode,
          tokens: tokens,
          morphFeature: morph!,
          multipleChoiceContent: multipleChoiceContent!,
          exampleMessageInfo: json['example_message_info'] != null
              ? ExampleMessageInfo.fromJson(json['example_message_info'])
              : const ExampleMessageInfo(exampleMessage: []),
        );
      case PracticeExerciseTypeEnum.lemmaAudio:
        assert(
          multipleChoiceContent != null,
          "multipleChoiceContent is null in PracticeExerciseModel.fromJson for lemmaAudio",
        );
        return VocabAudioPracticeExerciseModel(
          langCode: langCode,
          tokens: tokens,
          multipleChoiceContent: multipleChoiceContent!,
          roomId: json['room_id'] as String?,
          eventId: json['event_id'] as String?,
          exampleMessage: json['example_message'] != null
              ? ExampleMessageInfo.fromJson(json['example_message'])
              : const ExampleMessageInfo(exampleMessage: []),
        );
      case PracticeExerciseTypeEnum.lemmaMeaning:
        assert(
          multipleChoiceContent != null,
          "multipleChoiceContent is null in PracticeExerciseModel.fromJson for lemmaMeaning",
        );
        return VocabMeaningPracticeExerciseModel(
          langCode: langCode,
          tokens: tokens,
          multipleChoiceContent: multipleChoiceContent!,
        );
      case PracticeExerciseTypeEnum.emoji:
        assert(
          matchContent != null,
          "matchContent is null in PracticeExerciseModel.fromJson for emoji",
        );
        return EmojiPracticeExerciseModel(
          langCode: langCode,
          tokens: tokens,
          matchContent: matchContent!,
        );
      case PracticeExerciseTypeEnum.lemmaId:
        assert(
          multipleChoiceContent != null,
          "multipleChoiceContent is null in PracticeExerciseModel.fromJson for lemmaId",
        );
        return LemmaPracticeExerciseModel(
          langCode: langCode,
          tokens: tokens,
          multipleChoiceContent: multipleChoiceContent!,
        );
      case PracticeExerciseTypeEnum.wordMeaning:
        assert(
          matchContent != null,
          "matchContent is null in PracticeExerciseModel.fromJson for wordMeaning",
        );
        return LemmaMeaningPracticeExerciseModel(
          langCode: langCode,
          tokens: tokens,
          matchContent: matchContent!,
        );
      case PracticeExerciseTypeEnum.morphId:
        assert(
          morph != null,
          "morphFeature is null in PracticeExerciseModel.fromJson for morphId",
        );
        assert(
          multipleChoiceContent != null,
          "multipleChoiceContent is null in PracticeExerciseModel.fromJson for morphId",
        );
        return MorphMatchPracticeExerciseModel(
          langCode: langCode,
          tokens: tokens,
          morphFeature: morph!,
          multipleChoiceContent: multipleChoiceContent!,
        );
      case PracticeExerciseTypeEnum.wordFocusListening:
        assert(
          matchContent != null,
          "matchContent is null in PracticeExerciseModel.fromJson for wordFocusListening",
        );
        return WordListeningPracticeExerciseModel(
          langCode: langCode,
          tokens: tokens,
          matchContent: matchContent!,
        );
      case PracticeExerciseTypeEnum.grammarError:
        assert(
          multipleChoiceContent != null,
          "multipleChoiceContent is null in PracticeExerciseModel.fromJson for grammarError",
        );
        return GrammarErrorPracticeExerciseModel(
          langCode: langCode,
          tokens: tokens,
          multipleChoiceContent: multipleChoiceContent!,
          text: json['text'] as String,
          errorOffset: json['error_offset'] as int,
          errorLength: json['error_length'] as int,
          eventID: json['event_id'] as String,
          translation: json['translation'] as String,
        );
      default:
        throw ("Unsupported exercise type in PracticeExerciseModel.fromJson: $type");
    }
  }

  Map<String, dynamic> toJson() {
    return {
      ModelKey.langCode: langCode,
      'activity_type': exerciseType.name,
      'target_tokens': tokens.map((e) => e.toJson()).toList(),
    };
  }
}

sealed class MultipleChoicePracticeExerciseModel extends PracticeExerciseModel {
  final MultipleChoicePracticeExercise multipleChoiceContent;

  MultipleChoicePracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required this.multipleChoiceContent,
  });

  @override
  bool isCorrect(String choice, PangeaToken _) =>
      multipleChoiceContent.isCorrect(choice);

  List<OneConstructUse> constructUses(String choiceContent) {
    final correct = multipleChoiceContent.isCorrect(choiceContent);
    final useType = correct
        ? exerciseType.correctUse
        : exerciseType.incorrectUse;

    return tokens
        .map(
          (token) => OneConstructUse(
            useType: useType,
            constructType: exerciseType.constructUsesType,
            metadata: ConstructUseMetaData(
              roomId: null,
              timeStamp: DateTime.now(),
            ),
            category: token.pos,
            lemma: token.lemma.text,
            form: token.lemma.text,
            xp: useType.pointValue,
          ),
        )
        .toList();
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['content'] = multipleChoiceContent.toJson();
    return json;
  }
}

sealed class MatchPracticeExerciseModel extends PracticeExerciseModel {
  final MatchPracticeExercise matchContent;

  MatchPracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required this.matchContent,
  });

  @override
  bool isCorrect(String choice, PangeaToken token) =>
      matchContent.matchInfo[token.vocabForm]!.contains(choice);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['match_content'] = matchContent.toJson();
    return json;
  }
}

sealed class MorphPracticeExerciseModel
    extends MultipleChoicePracticeExerciseModel {
  final MorphFeaturesEnum morphFeature;

  MorphPracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required super.multipleChoiceContent,
    required this.morphFeature,
  });

  @override
  String get storageKey =>
      '${exerciseType.name}-${tokens.map((e) => e.text.content).join("-")}-${morphFeature.name}';

  @override
  List<OneConstructUse> constructUses(String choiceContent) {
    final correct = multipleChoiceContent.isCorrect(choiceContent);
    final useType = correct
        ? exerciseType.correctUse
        : exerciseType.incorrectUse;

    return tokens
        .map(
          (token) => OneConstructUse(
            useType: useType,
            constructType: exerciseType.constructUsesType,
            metadata: ConstructUseMetaData(
              roomId: null,
              timeStamp: DateTime.now(),
            ),
            category: morphFeature.name,
            lemma: token.getMorphTag(morphFeature)!,
            form: token.lemma.form,
            xp: useType.pointValue,
          ),
        )
        .toList();
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['morph_feature'] = morphFeature.name;
    return json;
  }
}

class MorphCategoryPracticeExerciseModel extends MorphPracticeExerciseModel {
  final ExampleMessageInfo exampleMessageInfo;
  MorphCategoryPracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required super.morphFeature,
    required super.multipleChoiceContent,
    required this.exampleMessageInfo,
  });

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['example_message_info'] = exampleMessageInfo.toJson();
    return json;
  }
}

class MorphMatchPracticeExerciseModel extends MorphPracticeExerciseModel {
  MorphMatchPracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required super.morphFeature,
    required super.multipleChoiceContent,
  });
}

class VocabAudioPracticeExerciseModel
    extends MultipleChoicePracticeExerciseModel {
  final String? roomId;
  final String? eventId;
  final ExampleMessageInfo exampleMessage;

  VocabAudioPracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required super.multipleChoiceContent,
    this.roomId,
    this.eventId,
    required this.exampleMessage,
  });

  @override
  List<OneConstructUse> constructUses(String choiceContent) {
    final correct = multipleChoiceContent.isCorrect(choiceContent);
    final useType = correct
        ? exerciseType.correctUse
        : exerciseType.incorrectUse;

    // For audio activities, find the token that matches the clicked word
    final matchingToken = tokens.firstWhere(
      (t) => t.text.content.toLowerCase() == choiceContent.toLowerCase(),
      orElse: () => tokens.first,
    );

    return [
      OneConstructUse(
        useType: useType,
        constructType: exerciseType.constructUsesType,
        metadata: ConstructUseMetaData(roomId: null, timeStamp: DateTime.now()),
        category: matchingToken.pos,
        lemma: matchingToken.lemma.text,
        form: matchingToken.lemma.text,
        xp: useType.pointValue,
      ),
    ];
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['room_id'] = roomId;
    json['event_id'] = eventId;
    json['example_message'] = exampleMessage.toJson();
    return json;
  }
}

class VocabMeaningPracticeExerciseModel
    extends MultipleChoicePracticeExerciseModel {
  VocabMeaningPracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required super.multipleChoiceContent,
  });
}

class LemmaPracticeExerciseModel extends MultipleChoicePracticeExerciseModel {
  LemmaPracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required super.multipleChoiceContent,
  });
}

class GrammarErrorPracticeExerciseModel
    extends MultipleChoicePracticeExerciseModel {
  final String text;
  final int errorOffset;
  final int errorLength;
  final String eventID;
  final String translation;

  GrammarErrorPracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required super.multipleChoiceContent,
    required this.text,
    required this.errorOffset,
    required this.errorLength,
    required this.eventID,
    required this.translation,
  });

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['text'] = text;
    json['error_offset'] = errorOffset;
    json['error_length'] = errorLength;
    json['event_id'] = eventID;
    json['translation'] = translation;
    return json;
  }
}

class EmojiPracticeExerciseModel extends MatchPracticeExerciseModel {
  EmojiPracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required super.matchContent,
  });
}

class LemmaMeaningPracticeExerciseModel extends MatchPracticeExerciseModel {
  LemmaMeaningPracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required super.matchContent,
  });
}

class WordListeningPracticeExerciseModel extends MatchPracticeExerciseModel {
  WordListeningPracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required super.matchContent,
  });
}

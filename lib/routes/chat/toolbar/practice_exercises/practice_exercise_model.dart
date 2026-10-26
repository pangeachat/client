import 'package:flutter/material.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/example_message_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_match.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/match_practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/multiple_choice_practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

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
      case ReadAloudPracticeExerciseModel():
        return PracticeExerciseTypeEnum.readAloud;
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
        ? MorphFeaturesEnum.fromString(json['morph_feature'] as String)
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
          translation: json['translation'] as String?,
        );
      case PracticeExerciseTypeEnum.readAloud:
        return ReadAloudPracticeExerciseModel(
          targetLemma: tokens.first.lemma.text,
          exampleTokens: (json['example_tokens'] as List? ?? const [])
              .map((e) => PangeaToken.fromJson(e as Map<String, dynamic>))
              .toList(),
          langCode: langCode,
          roomId: json['room_id'] as String?,
          eventId: json['event_id'] as String?,
          exampleMessage: json['example_message'] != null
              ? ExampleMessageInfo.fromJson(json['example_message'])
              : const ExampleMessageInfo(exampleMessage: []),
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
            metadata: constructUseMetadata,
            category: token.pos,
            lemma: token.lemma.text,
            form: token.lemma.text,
            xp: useType.pointValue,
          ),
        )
        .toList();
  }

  /// Metadata stamped onto each recorded practice use. Subclasses override to
  /// attach identifying context (e.g. the source [GrammarErrorPracticeExerciseModel]
  /// stamps its `eventID` so the 24-hour rotation rule can dedup by sentence).
  ConstructUseMetaData get constructUseMetadata =>
      ConstructUseMetaData(roomId: null, timeStamp: DateTime.now());

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

/// The read-aloud exercise: the learner reads [exampleTokens] aloud and the
/// target word must be heard (practice-exercises.instructions.md, "Speaking
/// practice").
///
/// A multiple-choice model with one hidden choice, the target's surface form,
/// which the learner's voice picks. That keeps the exercise inside the session
/// queue, answer recording and XP every other standalone exercise uses: a
/// heard target submits [heardAnswer] and records `corRA`; a miss submits
/// [notHeard] and records `incRA`.
class ReadAloudPracticeExerciseModel
    extends MultipleChoicePracticeExerciseModel {
  /// Every token of the displayed sentence, in order, punctuation included.
  final List<PangeaToken> exampleTokens;
  final String? roomId;
  final String? eventId;
  final ExampleMessageInfo exampleMessage;

  ReadAloudPracticeExerciseModel({
    required String targetLemma,
    required this.exampleTokens,
    required super.langCode,
    this.roomId,
    this.eventId,
    required this.exampleMessage,
  }) : super(
         tokens: [_targetIn(exampleTokens, targetLemma)],
         multipleChoiceContent: MultipleChoicePracticeExercise(
           choices: {_targetIn(exampleTokens, targetLemma).text.content},
           answers: {_targetIn(exampleTokens, targetLemma).text.content},
         ),
       );

  /// The sentence's token for [lemma]: the one the use is recorded against and
  /// the one the learner must be heard saying. Falls back to a bare token so a
  /// sentence that somehow lacks it still builds; [targetIndex] is then -1 and
  /// the generator swaps the exercise out.
  static PangeaToken _targetIn(List<PangeaToken> tokens, String lemma) =>
      tokens.firstWhere(
        (t) => t.lemma.text.toLowerCase() == lemma.toLowerCase(),
        orElse: () => PangeaToken(
          text: PangeaTokenText(content: lemma, offset: -1, length: 0),
          lemma: Lemma(text: lemma, saveVocab: true, form: lemma),
          pos: '',
          morph: const {},
        ),
      );

  /// The one answer: the target as it appears in the sentence.
  String get heardAnswer => tokens.first.text.content;

  /// The uses one recorded take earns. The target's read-aloud use, correct
  /// or not, decides the item; every other word heard earns the use a spoken
  /// word in a voice message earns, vocabulary only, and a word not heard
  /// earns nothing and is never a miss (practice-exercises.instructions.md,
  /// "What counts"). [heard] is per [referenceTokens].
  List<OneConstructUse> takeUses({
    required bool targetHeard,
    required List<bool> heard,
  }) {
    final uses = constructUses(targetHeard ? heardAnswer : notHeard);
    final target = tokens.first;
    final metadata = constructUseMetadata;
    final words = referenceTokens;
    const spoken = ConstructUseTypeEnum.pvm;
    for (var i = 0; i < words.length && i < heard.length; i++) {
      final token = words[i];
      final isTarget =
          token.text.offset == target.text.offset &&
          token.text.content == target.text.content;
      if (!heard[i] || isTarget || !token.lemma.saveVocab) continue;
      uses.add(
        OneConstructUse(
          useType: spoken,
          constructType: ConstructTypeEnum.vocab,
          metadata: metadata,
          category: token.pos,
          lemma: token.lemma.text,
          form: token.text.content,
          xp: spoken.pointValue,
        ),
      );
    }
    return uses;
  }

  /// Submitted for a miss. An empty string is never a spoken word, so it can
  /// never match the answer.
  static const String notHeard = '';

  /// The words the learner reads, in order: the sentence without its
  /// punctuation-only tokens.
  List<PangeaToken> get referenceTokens => [
    for (final token in exampleTokens)
      if (isSpokenWord(token.text.content)) token,
  ];

  /// The target's place in [referenceTokens], or -1 when it is not there.
  int get targetIndex {
    final target = tokens.first;
    return referenceTokens.indexWhere(
      (t) =>
          t.text.offset == target.text.offset &&
          t.text.content == target.text.content,
    );
  }

  /// The sentence as shown, for the reference audio and the hint. A trimmed
  /// example carries ellipsis marker spans; they are not read. Nothing else
  /// is dropped or trimmed, so index `i` here is message offset
  /// `exampleMessage.textOffset + i` and every token's offset maps onto it.
  String get referenceText => exampleMessage.exampleMessage
      .where((span) => !ExampleMessageUtil.isEllipsisMarker(span))
      .map((span) => span is TextSpan ? span.text ?? '' : '')
      .join();

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['room_id'] = roomId;
    json['event_id'] = eventId;
    json['example_message'] = exampleMessage.toJson();
    json['example_tokens'] = exampleTokens.map((e) => e.toJson()).toList();
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

  /// The sentence in the learner's L1, shown as the hint. Null in an offline
  /// session, because the translation needs the network.
  final String? translation;

  GrammarErrorPracticeExerciseModel({
    required super.tokens,
    required super.langCode,
    required super.multipleChoiceContent,
    required this.text,
    required this.errorOffset,
    required this.errorLength,
    required this.eventID,
    this.translation,
  });

  /// Stamp the source message's [eventID] onto each recorded practice use so
  /// [GrammarErrorTargetGenerator] can enforce the 24-hour rule by skipping any
  /// sentence (event) practiced within the cooldown, rather than relying on
  /// per-construct identity — which fails for ignored errors and multi-error
  /// messages (#7360).
  @override
  ConstructUseMetaData get constructUseMetadata => ConstructUseMetaData(
    roomId: null,
    timeStamp: DateTime.now(),
    eventId: eventID,
  );

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

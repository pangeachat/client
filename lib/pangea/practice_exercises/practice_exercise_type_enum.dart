import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';

enum PracticeExerciseTypeEnum {
  wordMeaning,
  wordFocusListening,
  hiddenWordListening,
  lemmaId,
  emoji,
  morphId,
  messageMeaning,
  lemmaMeaning,
  lemmaAudio,
  grammarCategory,
  grammarError;

  bool get includeTTSOnClick {
    switch (this) {
      case PracticeExerciseTypeEnum.wordMeaning:
      case PracticeExerciseTypeEnum.lemmaId:
      case PracticeExerciseTypeEnum.emoji:
      case PracticeExerciseTypeEnum.morphId:
      case PracticeExerciseTypeEnum.messageMeaning:
        return false;
      case PracticeExerciseTypeEnum.wordFocusListening:
      case PracticeExerciseTypeEnum.hiddenWordListening:
      case PracticeExerciseTypeEnum.lemmaAudio:
      case PracticeExerciseTypeEnum.lemmaMeaning:
      case PracticeExerciseTypeEnum.grammarCategory:
      case PracticeExerciseTypeEnum.grammarError:
        return true;
    }
  }

  static PracticeExerciseTypeEnum fromString(String value) {
    final split = value.split('.').last;
    switch (split) {
      // used to be called multiple_choice, but we changed it to word_meaning
      // as we now have multiple types of multiple choice activities
      // old data will still have multiple_choice so we need to handle that
      case 'multiple_choice':
      case 'multipleChoice':
      case 'word_meaning':
      case 'wordMeaning':
        return PracticeExerciseTypeEnum.wordMeaning;
      case 'word_focus_listening':
      case 'wordFocusListening':
        return PracticeExerciseTypeEnum.wordFocusListening;
      case 'hidden_word_listening':
      case 'hiddenWordListening':
        return PracticeExerciseTypeEnum.hiddenWordListening;
      case 'lemma_id':
        return PracticeExerciseTypeEnum.lemmaId;
      case 'emoji':
        return PracticeExerciseTypeEnum.emoji;
      case 'morph_id':
        return PracticeExerciseTypeEnum.morphId;
      case 'message_meaning':
        return PracticeExerciseTypeEnum.messageMeaning; // TODO: Add to L10n
      case 'lemma_meaning':
      case 'lemmaMeaning':
        return PracticeExerciseTypeEnum.lemmaMeaning;
      case 'lemma_audio':
      case 'lemmaAudio':
        return PracticeExerciseTypeEnum.lemmaAudio;
      case 'grammar_category':
      case 'grammarCategory':
        return PracticeExerciseTypeEnum.grammarCategory;
      case 'grammar_error':
      case 'grammarError':
        return PracticeExerciseTypeEnum.grammarError;
      default:
        throw Exception('Unknown exercise type: $split');
    }
  }

  List<ConstructUseTypeEnum> get associatedUseTypes {
    switch (this) {
      case PracticeExerciseTypeEnum.wordMeaning:
        return [
          ConstructUseTypeEnum.corPA,
          ConstructUseTypeEnum.incPA,
          ConstructUseTypeEnum.ignPA,
        ];
      case PracticeExerciseTypeEnum.wordFocusListening:
        return [
          ConstructUseTypeEnum.corWL,
          ConstructUseTypeEnum.incWL,
          ConstructUseTypeEnum.ignWL,
        ];
      case PracticeExerciseTypeEnum.hiddenWordListening:
        return [
          ConstructUseTypeEnum.corHWL,
          ConstructUseTypeEnum.incHWL,
          ConstructUseTypeEnum.ignHWL,
        ];
      case PracticeExerciseTypeEnum.lemmaId:
        return [
          ConstructUseTypeEnum.corL,
          ConstructUseTypeEnum.incL,
          ConstructUseTypeEnum.ignL,
        ];
      case PracticeExerciseTypeEnum.emoji:
        return [ConstructUseTypeEnum.em];
      case PracticeExerciseTypeEnum.morphId:
        return [
          ConstructUseTypeEnum.corM,
          ConstructUseTypeEnum.incM,
          ConstructUseTypeEnum.ignM,
        ];
      case PracticeExerciseTypeEnum.messageMeaning:
        return [
          ConstructUseTypeEnum.corMM,
          ConstructUseTypeEnum.incMM,
          ConstructUseTypeEnum.ignMM,
        ];
      case PracticeExerciseTypeEnum.lemmaAudio:
        return [ConstructUseTypeEnum.corLA, ConstructUseTypeEnum.incLA];
      case PracticeExerciseTypeEnum.lemmaMeaning:
        return [ConstructUseTypeEnum.corLM, ConstructUseTypeEnum.incLM];
      case PracticeExerciseTypeEnum.grammarCategory:
        return [ConstructUseTypeEnum.corGC, ConstructUseTypeEnum.incGC];
      case PracticeExerciseTypeEnum.grammarError:
        return [ConstructUseTypeEnum.corGE, ConstructUseTypeEnum.incGE];
    }
  }

  ConstructUseTypeEnum get correctUse {
    switch (this) {
      case PracticeExerciseTypeEnum.wordMeaning:
        return ConstructUseTypeEnum.corPA;
      case PracticeExerciseTypeEnum.wordFocusListening:
        return ConstructUseTypeEnum.corWL;
      case PracticeExerciseTypeEnum.hiddenWordListening:
        return ConstructUseTypeEnum.corHWL;
      case PracticeExerciseTypeEnum.lemmaId:
        return ConstructUseTypeEnum.corL;
      case PracticeExerciseTypeEnum.emoji:
        return ConstructUseTypeEnum.em;
      case PracticeExerciseTypeEnum.morphId:
        return ConstructUseTypeEnum.corM;
      case PracticeExerciseTypeEnum.messageMeaning:
        return ConstructUseTypeEnum.corMM;
      case PracticeExerciseTypeEnum.lemmaAudio:
        return ConstructUseTypeEnum.corLA;
      case PracticeExerciseTypeEnum.lemmaMeaning:
        return ConstructUseTypeEnum.corLM;
      case PracticeExerciseTypeEnum.grammarCategory:
        return ConstructUseTypeEnum.corGC;
      case PracticeExerciseTypeEnum.grammarError:
        return ConstructUseTypeEnum.corGE;
    }
  }

  ConstructUseTypeEnum get incorrectUse {
    switch (this) {
      case PracticeExerciseTypeEnum.wordMeaning:
        return ConstructUseTypeEnum.incPA;
      case PracticeExerciseTypeEnum.wordFocusListening:
        return ConstructUseTypeEnum.incWL;
      case PracticeExerciseTypeEnum.hiddenWordListening:
        return ConstructUseTypeEnum.incHWL;
      case PracticeExerciseTypeEnum.lemmaId:
        return ConstructUseTypeEnum.incL;
      case PracticeExerciseTypeEnum.emoji:
        return ConstructUseTypeEnum.em;
      case PracticeExerciseTypeEnum.morphId:
        return ConstructUseTypeEnum.incM;
      case PracticeExerciseTypeEnum.messageMeaning:
        return ConstructUseTypeEnum.incMM;
      case PracticeExerciseTypeEnum.lemmaAudio:
        return ConstructUseTypeEnum.incLA;
      case PracticeExerciseTypeEnum.lemmaMeaning:
        return ConstructUseTypeEnum.incLM;
      case PracticeExerciseTypeEnum.grammarCategory:
        return ConstructUseTypeEnum.incGC;
      case PracticeExerciseTypeEnum.grammarError:
        return ConstructUseTypeEnum.incGE;
    }
  }

  IconData get icon {
    switch (this) {
      case PracticeExerciseTypeEnum.wordMeaning:
      case PracticeExerciseTypeEnum.lemmaMeaning:
        return Icons.translate;
      case PracticeExerciseTypeEnum.wordFocusListening:
      case PracticeExerciseTypeEnum.hiddenWordListening:
      case PracticeExerciseTypeEnum.lemmaAudio:
        return Icons.volume_up;
      case PracticeExerciseTypeEnum.lemmaId:
        return Symbols.dictionary;
      case PracticeExerciseTypeEnum.emoji:
        return Icons.emoji_emotions;
      case PracticeExerciseTypeEnum.morphId:
        return Icons.format_shapes;
      case PracticeExerciseTypeEnum.messageMeaning:
      case PracticeExerciseTypeEnum.grammarCategory:
      case PracticeExerciseTypeEnum.grammarError:
        return Icons.star; // TODO: Add to L10n
    }
  }

  /// The minimum number of tokens in a message for this exercise type to be available.
  /// Matching exercises don't make sense for a single-word message.
  int get minTokensForMatchExercise {
    switch (this) {
      case PracticeExerciseTypeEnum.wordMeaning:
      case PracticeExerciseTypeEnum.lemmaId:
      case PracticeExerciseTypeEnum.wordFocusListening:
      case PracticeExerciseTypeEnum.emoji:
        return 2;
      case PracticeExerciseTypeEnum.hiddenWordListening:
      case PracticeExerciseTypeEnum.morphId:
      case PracticeExerciseTypeEnum.messageMeaning:
      case PracticeExerciseTypeEnum.lemmaMeaning:
      case PracticeExerciseTypeEnum.lemmaAudio:
      case PracticeExerciseTypeEnum.grammarCategory:
      case PracticeExerciseTypeEnum.grammarError:
        return 1;
    }
  }

  static List<PracticeExerciseTypeEnum> get practiceTypes => [
    PracticeExerciseTypeEnum.emoji,
    PracticeExerciseTypeEnum.wordMeaning,
    PracticeExerciseTypeEnum.wordFocusListening,
    PracticeExerciseTypeEnum.morphId,
  ];

  static List<PracticeExerciseTypeEnum> get _vocabPracticeTypes => [
    PracticeExerciseTypeEnum.lemmaMeaning,
    PracticeExerciseTypeEnum.lemmaAudio,
  ];

  static List<PracticeExerciseTypeEnum> get _grammarPracticeTypes => [
    PracticeExerciseTypeEnum.grammarCategory,
    PracticeExerciseTypeEnum.grammarError,
  ];

  static List<PracticeExerciseTypeEnum> analyticsPracticeTypes(
    ConstructTypeEnum constructType,
  ) {
    switch (constructType) {
      case ConstructTypeEnum.vocab:
        return _vocabPracticeTypes;
      case ConstructTypeEnum.morph:
        return _grammarPracticeTypes;
    }
  }

  /// The type of construct uses that these activities produce.
  /// NOTE: Grammar error activities create vocab uses, assosiated with the tokens in the
  /// targeted error span – NOT morph uses.
  ConstructTypeEnum get constructUsesType {
    switch (this) {
      case PracticeExerciseTypeEnum.grammarCategory:
      case PracticeExerciseTypeEnum.morphId:
        return ConstructTypeEnum.morph;
      default:
        return ConstructTypeEnum.vocab;
    }
  }
}

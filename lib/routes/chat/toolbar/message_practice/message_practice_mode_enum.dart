import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';

enum MessagePracticeMode {
  wordEmoji,
  wordMeaning,
  wordMorph,
  listening,
  noneSelected;

  IconData get icon {
    switch (this) {
      case MessagePracticeMode.listening:
        return Icons.volume_up;
      case MessagePracticeMode.wordMeaning:
        return Symbols.dictionary;
      case MessagePracticeMode.noneSelected:
        return Icons.error;
      case MessagePracticeMode.wordEmoji:
        return Symbols.imagesmode;
      case MessagePracticeMode.wordMorph:
        return Symbols.toys_and_games;
    }
  }

  String tooltip(BuildContext context) {
    switch (this) {
      case MessagePracticeMode.listening:
        return L10n.of(context).listen;
      case MessagePracticeMode.noneSelected:
        return '';
      case MessagePracticeMode.wordEmoji:
        return L10n.of(context).image;
      case MessagePracticeMode.wordMorph:
        return L10n.of(context).grammar;
      case MessagePracticeMode.wordMeaning:
        return L10n.of(context).meaning;
    }
  }

  /// What the tray asks once a blank is chosen. Naming the word keeps the
  /// exercise legible without the instruction banner.
  String prompt(BuildContext context, String word) {
    switch (this) {
      case MessagePracticeMode.listening:
        return L10n.of(context).practiceListeningPrompt(word);
      case MessagePracticeMode.wordMeaning:
        return L10n.of(context).practiceMeaningPrompt(word);
      case MessagePracticeMode.wordEmoji:
        return L10n.of(context).practiceEmojiPrompt(word);
      case MessagePracticeMode.wordMorph:
      case MessagePracticeMode.noneSelected:
        return '';
    }
  }

  Color iconButtonColor(BuildContext context, bool done) =>
      done ? AppConfig.gold : Theme.of(context).colorScheme.primaryContainer;

  PracticeExerciseTypeEnum? get associatedActivityType {
    switch (this) {
      case MessagePracticeMode.wordMeaning:
        return PracticeExerciseTypeEnum.wordMeaning;
      case MessagePracticeMode.listening:
        return PracticeExerciseTypeEnum.wordFocusListening;
      case MessagePracticeMode.wordEmoji:
        return PracticeExerciseTypeEnum.emoji;
      case MessagePracticeMode.wordMorph:
        return PracticeExerciseTypeEnum.morphId;
      case MessagePracticeMode.noneSelected:
        return null;
    }
  }

  static List<MessagePracticeMode> get practiceModes => [
    MessagePracticeMode.listening,
    MessagePracticeMode.wordMorph,
    MessagePracticeMode.wordMeaning,
    MessagePracticeMode.wordEmoji,
  ];

  InstructionsEnum? get instruction {
    switch (this) {
      case MessagePracticeMode.listening:
        return InstructionsEnum.chooseWordAudio;
      case MessagePracticeMode.wordMeaning:
        return InstructionsEnum.chooseLemmaMeaning;
      case MessagePracticeMode.wordEmoji:
        return InstructionsEnum.chooseEmoji;
      case MessagePracticeMode.wordMorph:
        return InstructionsEnum.chooseMorphs;
      default:
        return null;
    }
  }
}

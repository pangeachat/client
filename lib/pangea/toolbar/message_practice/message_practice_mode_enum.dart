import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';

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

  Color iconButtonColor(
    BuildContext context,
    bool done,
  ) =>
      done ? AppConfig.gold : Theme.of(context).colorScheme.primaryContainer;

  ActivityTypeEnum? get associatedActivityType {
    switch (this) {
      case MessagePracticeMode.wordMeaning:
        return ActivityTypeEnum.wordMeaning;
      case MessagePracticeMode.listening:
        return ActivityTypeEnum.wordFocusListening;
      case MessagePracticeMode.wordEmoji:
        return ActivityTypeEnum.emoji;
      case MessagePracticeMode.wordMorph:
        return ActivityTypeEnum.morphId;
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

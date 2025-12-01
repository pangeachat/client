import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';

enum MessageMode {
  wordEmoji,
  wordMeaning,
  wordMorph,
  listening,
  noneSelected;

  IconData get icon {
    switch (this) {
      case MessageMode.listening:
        return Icons.volume_up;
      case MessageMode.wordMeaning:
        return Symbols.dictionary;
      case MessageMode.noneSelected:
        return Icons.error;
      case MessageMode.wordEmoji:
        return Symbols.imagesmode;
      case MessageMode.wordMorph:
        return Symbols.toys_and_games;
    }
  }

  String tooltip(BuildContext context) {
    switch (this) {
      case MessageMode.listening:
        return L10n.of(context).listen;
      case MessageMode.noneSelected:
        return '';
      case MessageMode.wordEmoji:
        return L10n.of(context).image;
      case MessageMode.wordMorph:
        return L10n.of(context).grammar;
      case MessageMode.wordMeaning:
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
      case MessageMode.wordMeaning:
        return ActivityTypeEnum.wordMeaning;
      case MessageMode.listening:
        return ActivityTypeEnum.wordFocusListening;
      case MessageMode.wordEmoji:
        return ActivityTypeEnum.emoji;
      case MessageMode.wordMorph:
        return ActivityTypeEnum.morphId;
      case MessageMode.noneSelected:
        return null;
    }
  }

  static List<MessageMode> get practiceModes => [
        MessageMode.listening,
        MessageMode.wordMorph,
        MessageMode.wordMeaning,
        MessageMode.wordEmoji,
      ];
}

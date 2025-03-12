import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/toolbar/enums/activity_type_enum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:material_symbols_icons/symbols.dart';

enum MessageMode {
  practiceActivity,

  wordZoom,
  wordEmoji,
  wordMeaning,
  wordMorph,
  // wordZoomTextToSpeech,
  // wordZoomSpeechToText,

  messageMeaning,
  messageTextToSpeech,
  messageSpeechToText,
  messageTranslation,

  // message not selected
  noneSelected,
}

extension MessageModeExtension on MessageMode {
  IconData get icon {
    switch (this) {
      case MessageMode.messageTranslation:
        return Icons.translate;
      case MessageMode.messageTextToSpeech:
        return Icons.hearing;
      case MessageMode.messageSpeechToText:
        return Symbols.speech_to_text;
      case MessageMode.practiceActivity:
        return Symbols.fitness_center;
      case MessageMode.wordZoom:
      case MessageMode.wordMeaning:
        return Symbols.translate;
      case MessageMode.noneSelected:
        return Icons.error;
      case MessageMode.messageMeaning:
        return Icons.star;
      case MessageMode.wordEmoji:
        return Icons.emoji_emotions;
      case MessageMode.wordMorph:
        return Symbols.toys_and_games;
    }
  }

  String title(BuildContext context) {
    switch (this) {
      case MessageMode.messageTranslation:
        return L10n.of(context).translations;
      case MessageMode.messageTextToSpeech:
        return L10n.of(context).messageAudio;
      case MessageMode.messageSpeechToText:
        return L10n.of(context).speechToTextTooltip;
      case MessageMode.practiceActivity:
        return L10n.of(context).practice;
      case MessageMode.wordZoom:
        return L10n.of(context).vocab;
      case MessageMode.noneSelected:
        return '';
      case MessageMode.messageMeaning:
        return L10n.of(context).meaning;
      //TODO: add L10n
      case MessageMode.wordEmoji:
        return "Emoji";
      case MessageMode.wordMorph:
        return "Morph";
      case MessageMode.wordMeaning:
        return "Meaning";
    }
  }

  String tooltip(BuildContext context) {
    switch (this) {
      case MessageMode.messageTranslation:
        return L10n.of(context).translationTooltip;
      case MessageMode.messageTextToSpeech:
        return L10n.of(context).audioTooltip;
      case MessageMode.messageSpeechToText:
        return L10n.of(context).speechToTextTooltip;
      case MessageMode.practiceActivity:
        return L10n.of(context).practice;
      case MessageMode.wordZoom:
        return L10n.of(context).vocab;
      case MessageMode.noneSelected:
        return '';
      case MessageMode.messageMeaning:
        return L10n.of(context).meaning;
      //TODO: add L10n
      case MessageMode.wordEmoji:
        return "Emoji";
      case MessageMode.wordMorph:
        return "Morph";
      case MessageMode.wordMeaning:
        return "Meaning";
    }
  }

  InstructionsEnum get instructionsEnum {
    switch (this) {
      case MessageMode.wordMorph:
        return InstructionsEnum.chooseMorphs;
      case MessageMode.messageSpeechToText:
        return InstructionsEnum.speechToText;
      case MessageMode.messageTranslation:
      case MessageMode.wordMeaning:
        return InstructionsEnum.chooseLemmaMeaning;
      case MessageMode.messageTextToSpeech:
        return InstructionsEnum.chooseWordAudio;
      case MessageMode.wordEmoji:
        return InstructionsEnum.chooseEmoji;
      case MessageMode.noneSelected:
      case MessageMode.messageMeaning:
      case MessageMode.wordZoom:
      case MessageMode.practiceActivity:
        return InstructionsEnum.clickMessage;
    }
  }

  double get pointOnBar {
    switch (this) {
      // case MessageMode.stats:
      //   return 1;
      case MessageMode.noneSelected:
        return 1;
      case MessageMode.wordMorph:
        return 0.7;
      case MessageMode.wordMeaning:
        return 0.5;
      case MessageMode.messageTextToSpeech:
        return 0.3;
      case MessageMode.messageTranslation:
      case MessageMode.messageSpeechToText:
      case MessageMode.wordZoom:
      case MessageMode.wordEmoji:
      case MessageMode.messageMeaning:
      case MessageMode.practiceActivity:
        return 0;
    }
  }

  bool isUnlocked(
    double proportionOfActivitiesCompleted,
    bool totallyDone,
  ) {
    switch (this) {
      case MessageMode.messageTranslation:
      case MessageMode.messageTextToSpeech:
        return proportionOfActivitiesCompleted >= pointOnBar || totallyDone;
      case MessageMode.practiceActivity:
        return !totallyDone;
      case MessageMode.messageSpeechToText:
      case MessageMode.messageMeaning:
      case MessageMode.wordZoom:
      case MessageMode.wordEmoji:
      case MessageMode.wordMorph:
      case MessageMode.wordMeaning:
      case MessageMode.noneSelected:
        return true;
    }
  }

  bool get showButton => this != MessageMode.practiceActivity;

  Color iconButtonColor(
    BuildContext context,
    MessageMode currentMode,
    double proportionOfActivitiesUnlocked,
    bool totallyDone,
  ) {
    if (this == MessageMode.practiceActivity && totallyDone) {
      return AppConfig.gold;
    }

    //locked
    if (!isUnlocked(proportionOfActivitiesUnlocked, totallyDone)) {
      return barAndLockedButtonColor(context);
    }

    //unlocked and active
    if (this == currentMode) {
      return totallyDone ? AppConfig.gold : AppConfig.primaryColorLight;
    }

    //unlocked and inactive
    return Theme.of(context).colorScheme.primaryContainer;
  }

  static Color barAndLockedButtonColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.grey[800]!
        : Colors.grey[200]!;
  }

  ActivityTypeEnum? get associatedActivityType {
    switch (this) {
      case MessageMode.wordMeaning:
        return ActivityTypeEnum.wordMeaning;
      case MessageMode.messageTextToSpeech:
        return ActivityTypeEnum.wordFocusListening;

      case MessageMode.wordEmoji:
        return ActivityTypeEnum.emoji;

      case MessageMode.wordMorph:
        return ActivityTypeEnum.morphId;

      case MessageMode.noneSelected:
      case MessageMode.messageMeaning:
      case MessageMode.messageTranslation:
      case MessageMode.wordZoom:
      case MessageMode.messageSpeechToText:
      case MessageMode.practiceActivity:
        return null;
    }
  }
}

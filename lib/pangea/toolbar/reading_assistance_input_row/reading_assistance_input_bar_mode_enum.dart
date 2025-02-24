import 'dart:developer';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/toolbar/enums/activity_type_enum.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:flutter/foundation.dart';

enum ReadingAssistanceModeEnum {
  //full selection of emojis that have been unlocked, one for each token in the message
  // allows the learner to send that emoji to the message with a longpress or double-tap
  // or they can navigate to the word views with a single tap
  messageEmojiChoice,

  // after selecting a seed emoji, you are presented with a choice of 4-5 relevant emojis to mark it with
  // and choosing the emoji for the word, you get a seed (not XP)
  // after getting the seed, the selection goes back to the whole message
  wordEmojiChoice,

  // after selecting an emoji, you are presented with a choice of 4-5 meanings for the word
  // and choosing the meaning for the word, you get from 1-5 total XP depending on your choices
  wordMeaningChoice,

  // for languages that have a different script, you can choose to listen to the word being pronounced
  // and choosing which word you hear
  // distractors are selected for semantic similarity rather than phonetic similarity
  // this puts less burden on the tts system to be super precise
  // wordListening,

  // at this point you get a hidden word listening activity
  // messageListening,

  // for languages that have a different script, you can choose to listen to the word being pronounced
  // and then pronouncing it yourself. you can record as much as you want
  // the goal is to replace the shitty tts with your own voice eventually
  // wordPronunciation,

  // now they get a part of speech activity and then the rest of the morphs
  // selections include icons and names
  morph,

  // if you want, you can spend a star to get the message translated immediately
  messageMeaning
}

extension WordZoomSelectionUtils on ReadingAssistanceModeEnum {
  ActivityTypeEnum get activityType {
    switch (this) {
      case ReadingAssistanceModeEnum.wordMeaningChoice:
        return ActivityTypeEnum.wordMeaning;
      case ReadingAssistanceModeEnum.wordEmojiChoice:
        return ActivityTypeEnum.emoji;
      case ReadingAssistanceModeEnum.messageMeaning:
        return ActivityTypeEnum.messageMeaning;
      case ReadingAssistanceModeEnum.morph:
        return ActivityTypeEnum.morphId;
      case ReadingAssistanceModeEnum.messageEmojiChoice:
        debugger(when: kDebugMode);
        ErrorHandler.logError(
          m: "messageEmojiChoice has any activityType, should not be here",
          data: {},
        );
        return ActivityTypeEnum.emoji;
    }
  }

  static ReadingAssistanceModeEnum fromMessageMode(MessageMode messageMode) {
    switch (messageMode) {
      case MessageMode.messageMeaning:
      case MessageMode.practiceActivity:
      case MessageMode.textToSpeech:
      case MessageMode.translation:
      case MessageMode.speechToText:
      case MessageMode.noneSelected:
        return ReadingAssistanceModeEnum.messageEmojiChoice;
      case MessageMode.wordZoom:
        return ReadingAssistanceModeEnum.wordEmojiChoice;
    }
  }
}

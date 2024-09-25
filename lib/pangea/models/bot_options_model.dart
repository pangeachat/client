import 'dart:developer';

import 'package:fluffychat/pangea/constants/bot_mode.dart';
import 'package:fluffychat/pangea/constants/model_keys.dart';
import 'package:fluffychat/pangea/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class BotOptionsModel {
  int? languageLevel;
  String topic;
  List<String> keywords;
  bool safetyModeration;
  String mode;
  String? discussionTopic;
  String? discussionKeywords;
  bool? discussionTriggerReactionEnabled;
  String? discussionTriggerReactionKey;
  String? customSystemPrompt;
  bool? customTriggerReactionEnabled;
  String? customTriggerReactionKey;
  String? textAdventureGameMasterInstructions;

  BotOptionsModel({
    ////////////////////////////////////////////////////////////////////////////
    // General Bot Options
    ////////////////////////////////////////////////////////////////////////////
    this.languageLevel,
    this.topic = "General Conversation",
    this.keywords = const [],
    this.safetyModeration = true,
    this.mode = BotMode.discussion,

    ////////////////////////////////////////////////////////////////////////////
    // Discussion Mode Options
    ////////////////////////////////////////////////////////////////////////////
    this.discussionTopic,
    this.discussionKeywords,
    this.discussionTriggerReactionEnabled = true,
    this.discussionTriggerReactionKey = "⏩",

    ////////////////////////////////////////////////////////////////////////////
    // Custom Mode Options
    ////////////////////////////////////////////////////////////////////////////
    this.customSystemPrompt,
    this.customTriggerReactionEnabled = true,
    this.customTriggerReactionKey = "⏩",

    ////////////////////////////////////////////////////////////////////////////
    // Text Adventure Mode Options
    ////////////////////////////////////////////////////////////////////////////
    this.textAdventureGameMasterInstructions,
  });

  factory BotOptionsModel.fromJson(json) {
    return BotOptionsModel(
      //////////////////////////////////////////////////////////////////////////
      // General Bot Options
      //////////////////////////////////////////////////////////////////////////
      languageLevel: json[ModelKey.languageLevel] is int
          ? json[ModelKey.languageLevel]
          : null,
      safetyModeration: json[ModelKey.safetyModeration] ?? true,
      mode: json[ModelKey.mode] ?? BotMode.discussion,

      //////////////////////////////////////////////////////////////////////////
      // Discussion Mode Options
      //////////////////////////////////////////////////////////////////////////
      discussionTopic: json[ModelKey.discussionTopic],
      discussionKeywords: json[ModelKey.discussionKeywords],
      discussionTriggerReactionEnabled:
          json[ModelKey.discussionTriggerReactionEnabled] ?? true,
      discussionTriggerReactionKey:
          json[ModelKey.discussionTriggerReactionKey] ?? "⏩",

      //////////////////////////////////////////////////////////////////////////
      // Custom Mode Options
      //////////////////////////////////////////////////////////////////////////
      customSystemPrompt: json[ModelKey.customSystemPrompt],
      customTriggerReactionEnabled:
          json[ModelKey.customTriggerReactionEnabled] ?? true,
      customTriggerReactionKey: json[ModelKey.customTriggerReactionKey] ?? "⏩",

      //////////////////////////////////////////////////////////////////////////
      // Text Adventure Mode Options
      //////////////////////////////////////////////////////////////////////////
      textAdventureGameMasterInstructions:
          json[ModelKey.textAdventureGameMasterInstructions],
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    try {
      // data[ModelKey.isConversationBotChat] = isConversationBotChat;
      data[ModelKey.languageLevel] = languageLevel;
      data[ModelKey.safetyModeration] = safetyModeration;
      data[ModelKey.mode] = mode;
      data[ModelKey.discussionTopic] = discussionTopic;
      data[ModelKey.discussionKeywords] = discussionKeywords;
      data[ModelKey.discussionTriggerReactionEnabled] =
          discussionTriggerReactionEnabled ?? true;
      data[ModelKey.discussionTriggerReactionKey] =
          discussionTriggerReactionKey ?? "⏩";
      data[ModelKey.customSystemPrompt] = customSystemPrompt;
      data[ModelKey.customTriggerReactionEnabled] =
          customTriggerReactionEnabled ?? true;
      data[ModelKey.customTriggerReactionKey] = customTriggerReactionKey ?? "⏩";
      data[ModelKey.textAdventureGameMasterInstructions] =
          textAdventureGameMasterInstructions;
      return data;
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(e: e, s: s);
      return data;
    }
  }

  //TODO: define enum with all possible values
  updateBotOption(String key, dynamic value) {
    switch (key) {
      case ModelKey.languageLevel:
        languageLevel = value;
        break;
      case ModelKey.safetyModeration:
        safetyModeration = value;
        break;
      case ModelKey.mode:
        mode = value;
        break;
      case ModelKey.discussionTopic:
        discussionTopic = value;
        break;
      case ModelKey.discussionKeywords:
        discussionKeywords = value;
        break;
      case ModelKey.discussionTriggerReactionEnabled:
        discussionTriggerReactionEnabled = value;
        break;
      case ModelKey.discussionTriggerReactionKey:
        discussionTriggerReactionKey = value;
        break;
      case ModelKey.customSystemPrompt:
        customSystemPrompt = value;
        break;
      case ModelKey.customTriggerReactionEnabled:
        customTriggerReactionEnabled = value;
        break;
      case ModelKey.customTriggerReactionKey:
        customTriggerReactionKey = value;
        break;
      case ModelKey.textAdventureGameMasterInstructions:
        textAdventureGameMasterInstructions = value;
        break;
      default:
        throw Exception('Invalid key for bot options - $key');
    }
  }

  StateEvent get toStateEvent => StateEvent(
        content: toJson(),
        type: PangeaEventTypes.botOptions,
      );
}

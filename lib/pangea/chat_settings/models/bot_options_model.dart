import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/pangea/chat_settings/constants/bot_mode.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/learning_settings/gender_enum.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';

class BotOptionsModel {
  final LanguageLevelTypeEnum languageLevel;
  final String topic;
  final List<String> keywords;
  final bool safetyModeration;
  final String mode;
  final String? discussionTopic;
  final String? discussionKeywords;
  final bool? discussionTriggerReactionEnabled;
  final String? discussionTriggerReactionKey;
  final String? customSystemPrompt;
  final bool? customTriggerReactionEnabled;
  final String? customTriggerReactionKey;
  final String? textAdventureGameMasterInstructions;
  final String? targetLanguage;
  final String? targetVoice;
  final GenderEnum targetGender;

  const BotOptionsModel({
    ////////////////////////////////////////////////////////////////////////////
    // General Bot Options
    ////////////////////////////////////////////////////////////////////////////
    this.languageLevel = LanguageLevelTypeEnum.a1,
    this.topic = "General Conversation",
    this.keywords = const [],
    this.safetyModeration = true,
    this.mode = BotMode.discussion,
    this.targetLanguage,
    this.targetVoice,
    this.targetGender = GenderEnum.unselected,

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
          ? LanguageLevelTypeEnum.fromInt(json[ModelKey.languageLevel])
          : json[ModelKey.languageLevel] is String
              ? LanguageLevelTypeEnum.fromString(
                  json[ModelKey.languageLevel],
                )
              : LanguageLevelTypeEnum.a1,
      safetyModeration: json[ModelKey.safetyModeration] ?? true,
      mode: json[ModelKey.mode] ?? BotMode.discussion,
      targetLanguage: json[ModelKey.targetLanguage],
      targetVoice: json[ModelKey.targetVoice],
      targetGender: json[ModelKey.targetGender] != null
          ? GenderEnum.values.firstWhere(
              (g) => g.name == json[ModelKey.targetGender],
              orElse: () => GenderEnum.unselected,
            )
          : GenderEnum.unselected,

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
      data[ModelKey.languageLevel] = languageLevel.storageInt;
      data[ModelKey.safetyModeration] = safetyModeration;
      data[ModelKey.mode] = mode;
      data[ModelKey.targetLanguage] = targetLanguage;
      data[ModelKey.targetVoice] = targetVoice;
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
      data[ModelKey.targetGender] = targetGender.name;
      return data;
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        e: e,
        s: s,
        data: data,
      );
      return data;
    }
  }

  BotOptionsModel copyWith({
    LanguageLevelTypeEnum? languageLevel,
    String? topic,
    List<String>? keywords,
    bool? safetyModeration,
    String? mode,
    String? discussionTopic,
    String? discussionKeywords,
    bool? discussionTriggerReactionEnabled,
    String? discussionTriggerReactionKey,
    String? customSystemPrompt,
    bool? customTriggerReactionEnabled,
    String? customTriggerReactionKey,
    String? textAdventureGameMasterInstructions,
    String? targetLanguage,
    String? targetVoice,
    GenderEnum? targetGender,
  }) {
    return BotOptionsModel(
      languageLevel: languageLevel ?? this.languageLevel,
      topic: topic ?? this.topic,
      keywords: keywords ?? this.keywords,
      safetyModeration: safetyModeration ?? this.safetyModeration,
      mode: mode ?? this.mode,
      discussionTopic: discussionTopic ?? this.discussionTopic,
      discussionKeywords: discussionKeywords ?? this.discussionKeywords,
      discussionTriggerReactionEnabled: discussionTriggerReactionEnabled ??
          this.discussionTriggerReactionEnabled,
      discussionTriggerReactionKey:
          discussionTriggerReactionKey ?? this.discussionTriggerReactionKey,
      customSystemPrompt: customSystemPrompt ?? this.customSystemPrompt,
      customTriggerReactionEnabled:
          customTriggerReactionEnabled ?? this.customTriggerReactionEnabled,
      customTriggerReactionKey:
          customTriggerReactionKey ?? this.customTriggerReactionKey,
      textAdventureGameMasterInstructions:
          textAdventureGameMasterInstructions ??
              this.textAdventureGameMasterInstructions,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      targetVoice: targetVoice ?? this.targetVoice,
      targetGender: targetGender ?? this.targetGender,
    );
  }
}

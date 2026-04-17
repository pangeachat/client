import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/pangea/chat_settings/constants/bot_constants.dart';
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
  final Map<String, GenderEnum> userGenders;

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
    this.userGenders = const {},

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

  factory BotOptionsModel.fromJson(Map<String, dynamic> json) {
    final genderEntry = json[BotConstants.targetGender];
    Map<String, GenderEnum> targetGenders = {};
    if (genderEntry is Map<String, dynamic>) {
      targetGenders = Map<String, GenderEnum>.fromEntries(
        genderEntry.entries.map(
          (e) => MapEntry(
            e.key,
            GenderEnum.values.firstWhere(
              (g) => g.name == e.value,
              orElse: () => GenderEnum.unselected,
            ),
          ),
        ),
      );
    }

    return BotOptionsModel(
      //////////////////////////////////////////////////////////////////////////
      // General Bot Options
      //////////////////////////////////////////////////////////////////////////
      languageLevel: json[BotConstants.languageLevel] is int
          ? LanguageLevelTypeEnum.fromInt(json[BotConstants.languageLevel])
          : json[BotConstants.languageLevel] is String
          ? LanguageLevelTypeEnum.fromString(json[BotConstants.languageLevel])
          : LanguageLevelTypeEnum.a1,
      safetyModeration: json[BotConstants.safetyModeration] ?? true,
      mode: json[BotConstants.mode] ?? BotMode.discussion,
      targetLanguage: json[ModelKey.targetLanguage],
      targetVoice: json[BotConstants.targetVoice],
      userGenders: targetGenders,

      //////////////////////////////////////////////////////////////////////////
      // Discussion Mode Options
      //////////////////////////////////////////////////////////////////////////
      discussionTopic: json[BotConstants.discussionTopic],
      discussionKeywords: json[BotConstants.discussionKeywords],
      discussionTriggerReactionEnabled:
          json[BotConstants.discussionTriggerReactionEnabled] ?? true,
      discussionTriggerReactionKey:
          json[BotConstants.discussionTriggerReactionKey] ?? "⏩",

      //////////////////////////////////////////////////////////////////////////
      // Custom Mode Options
      //////////////////////////////////////////////////////////////////////////
      customSystemPrompt: json[BotConstants.customSystemPrompt],
      customTriggerReactionEnabled:
          json[BotConstants.customTriggerReactionEnabled] ?? true,
      customTriggerReactionKey:
          json[BotConstants.customTriggerReactionKey] ?? "⏩",

      //////////////////////////////////////////////////////////////////////////
      // Text Adventure Mode Options
      //////////////////////////////////////////////////////////////////////////
      textAdventureGameMasterInstructions:
          json[BotConstants.textAdventureGameMasterInstructions],
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    try {
      final Map<String, String> gendersEntry = {};
      for (final entry in userGenders.entries) {
        gendersEntry[entry.key] = entry.value.name;
      }

      // data[ModelKey.isConversationBotChat] = isConversationBotChat;
      data[BotConstants.languageLevel] = languageLevel.storageInt;
      data[BotConstants.safetyModeration] = safetyModeration;
      data[BotConstants.mode] = mode;
      data[ModelKey.targetLanguage] = targetLanguage;
      data[BotConstants.targetVoice] = targetVoice;
      data[BotConstants.discussionTopic] = discussionTopic;
      data[BotConstants.discussionKeywords] = discussionKeywords;
      data[BotConstants.discussionTriggerReactionEnabled] =
          discussionTriggerReactionEnabled ?? true;
      data[BotConstants.discussionTriggerReactionKey] =
          discussionTriggerReactionKey ?? "⏩";
      data[BotConstants.customSystemPrompt] = customSystemPrompt;
      data[BotConstants.customTriggerReactionEnabled] =
          customTriggerReactionEnabled ?? true;
      data[BotConstants.customTriggerReactionKey] =
          customTriggerReactionKey ?? "⏩";
      data[BotConstants.textAdventureGameMasterInstructions] =
          textAdventureGameMasterInstructions;
      data[BotConstants.targetGender] = gendersEntry;
      return data;
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(e: e, s: s, data: data);
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
    Map<String, GenderEnum>? userGenders,
  }) {
    return BotOptionsModel(
      languageLevel: languageLevel ?? this.languageLevel,
      topic: topic ?? this.topic,
      keywords: keywords ?? this.keywords,
      safetyModeration: safetyModeration ?? this.safetyModeration,
      mode: mode ?? this.mode,
      discussionTopic: discussionTopic ?? this.discussionTopic,
      discussionKeywords: discussionKeywords ?? this.discussionKeywords,
      discussionTriggerReactionEnabled:
          discussionTriggerReactionEnabled ??
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
      userGenders: userGenders ?? this.userGenders,
    );
  }
}

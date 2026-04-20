import 'package:fluffychat/pangea/analytics_misc/analytics_constants.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';

class AnalyticsProfileModel {
  LanguageModel? baseLanguage;
  LanguageModel? targetLanguage;
  Map<LanguageModel, LanguageAnalyticsProfileEntry>? languageAnalytics;

  AnalyticsProfileModel({
    this.baseLanguage,
    this.targetLanguage,
    this.languageAnalytics,
  });

  factory AnalyticsProfileModel.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey(PangeaEventTypes.profileAnalytics)) {
      return AnalyticsProfileModel();
    }

    final profileJson = json[PangeaEventTypes.profileAnalytics];

    final baseLanguage = profileJson[ModelKey.sourceLanguage] != null
        ? PLanguageStore.byLangCode(profileJson[ModelKey.sourceLanguage])
        : null;

    final targetLanguage = profileJson[ModelKey.targetLanguage] != null
        ? PLanguageStore.byLangCode(profileJson[ModelKey.targetLanguage])
        : null;

    final languageAnalytics = <LanguageModel, LanguageAnalyticsProfileEntry>{};
    if (profileJson[AnalyticsConstants.analytics] != null &&
        profileJson[AnalyticsConstants.analytics]!.isNotEmpty) {
      for (final entry in profileJson[AnalyticsConstants.analytics].entries) {
        final lang = PLanguageStore.byLangCode(entry.key);
        if (lang == null) continue;
        final level = entry.value[AnalyticsConstants.level];
        final xpOffset = entry.value[AnalyticsConstants.xpOffset] ?? 0;
        final analyticsRoomId =
            entry.value[AnalyticsConstants.analyticsRoomId] as String?;
        languageAnalytics[lang] = LanguageAnalyticsProfileEntry(
          level,
          xpOffset,
          analyticsRoomId: analyticsRoomId,
        );
      }
    }

    final profile = AnalyticsProfileModel(
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
      languageAnalytics: languageAnalytics,
    );
    return profile;
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (targetLanguage != null) {
      json[ModelKey.targetLanguage] = targetLanguage!.langCodeShort;
    }

    if (baseLanguage != null) {
      json[ModelKey.sourceLanguage] = baseLanguage!.langCodeShort;
    }

    final analytics = {};
    if (languageAnalytics != null && languageAnalytics!.isNotEmpty) {
      for (final entry in languageAnalytics!.entries) {
        analytics[entry.key.langCode] = {
          AnalyticsConstants.level: entry.value.level,
          AnalyticsConstants.xpOffset: entry.value.xpOffset,
          if (entry.value.analyticsRoomId != null)
            AnalyticsConstants.analyticsRoomId: entry.value.analyticsRoomId,
        };
      }
    }

    json[AnalyticsConstants.analytics] = analytics;
    return json;
  }

  bool get isEmpty =>
      baseLanguage == null ||
      targetLanguage == null ||
      (languageAnalytics == null || languageAnalytics!.isEmpty);

  String? analyticsRoomIdByLanguage(LanguageModel language) =>
      languageAnalytics![language]?.analyticsRoomId;

  /// Set the level and analytics room ID for the a given language.
  void setLanguageInfo(
    LanguageModel language,
    int level,
    String? analyticsRoomId,
  ) {
    languageAnalytics ??= {};
    languageAnalytics![language] ??= LanguageAnalyticsProfileEntry(
      0,
      0,
      analyticsRoomId: analyticsRoomId,
    );

    if (languageAnalytics![language]!.level < level) {
      languageAnalytics![language]!.level = level;
    }

    final currentRoomId = analyticsRoomIdByLanguage(language);
    if (currentRoomId != analyticsRoomId) {
      languageAnalytics![language]!.analyticsRoomId = analyticsRoomId;
    }
    languageAnalytics![language]!.level = level;
  }

  void addXPOffset(
    LanguageModel language,
    int xpOffset,
    String? analyticsRoomId,
  ) {
    languageAnalytics ??= {};
    languageAnalytics![language] ??= LanguageAnalyticsProfileEntry(
      0,
      0,
      analyticsRoomId: analyticsRoomId,
    );

    final currentRoomId = analyticsRoomIdByLanguage(language);
    if (currentRoomId == null) {
      languageAnalytics![language]!.analyticsRoomId = analyticsRoomId;
    }
    languageAnalytics![language]!.xpOffset += xpOffset;
  }

  int? get level => languageAnalytics?[targetLanguage]?.level;

  int? get xpOffset => languageAnalytics?[targetLanguage]?.xpOffset;

  int? xpOffsetByLanguage(LanguageModel language) =>
      languageAnalytics?[language]?.xpOffset;
}

class LanguageAnalyticsProfileEntry {
  int level;
  int xpOffset = 0;
  String? analyticsRoomId;

  LanguageAnalyticsProfileEntry(
    this.level,
    this.xpOffset, {
    this.analyticsRoomId,
  });
}

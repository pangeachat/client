import 'package:fluffychat/features/analytics/analytics_constants.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// The publicly-readable mirror of a learner's analytics: their level and XP
/// offset per language, plus the id of each language's analytics room.
///
/// It is a mirror, never a source. The source of truth is the per-language
/// local analytics partition and Matrix analytics room, neither of which other
/// users can read — this exists so classmates and instructors can see a level
/// at all (profile.instructions.md, "Ownership and mirroring").
///
/// **Keyed per language, by short code** (`fr`, not `fr-CA`). Analytics rooms
/// and local partitions are per language, so every regional variant of a
/// language shares one XP total and must show one level; keying per locale gave
/// `fr`, `fr-FR` and `fr-CA` three independent, separately-stale entries
/// (#8582). Keys are raw strings rather than [LanguageModel] both because that
/// is the grain the data actually has, and because resolving them through
/// [PLanguageStore] made parsing depend on the language list having loaded —
/// before it had, every entry was silently dropped and the next write published
/// the empty result over the learner's real history.
class AnalyticsProfileModel {
  /// Short language codes, mirroring the learner's current settings. Raw
  /// strings for the same reason the map keys are.
  String? baseLanguage;
  String? targetLanguage;
  Map<String, LanguageAnalyticsProfileEntry>? languageAnalytics;

  AnalyticsProfileModel({
    this.baseLanguage,
    this.targetLanguage,
    this.languageAnalytics,
  });

  static String _shortCode(String langCode) => langCode.split('-').first;

  factory AnalyticsProfileModel.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey(PangeaEventTypes.profileAnalytics)) {
      return AnalyticsProfileModel();
    }

    final profileJson = json[PangeaEventTypes.profileAnalytics];

    final languageAnalytics = <String, LanguageAnalyticsProfileEntry>{};
    final analyticsJson = profileJson[AnalyticsConstants.analytics];
    if (analyticsJson is Map) {
      for (final entry in analyticsJson.entries) {
        final value = entry.value;
        if (entry.key is! String || value is! Map) continue;

        // Profiles written before #8582 carry a key per locale. Collapse them
        // onto the language: the largest level wins, since every variant was
        // reporting on one shared XP total and the highest is the one that saw
        // it most recently.
        final key = _shortCode(entry.key as String);
        final existing = languageAnalytics[key];
        final level = value[AnalyticsConstants.level] as int? ?? 0;
        final xpOffset = value[AnalyticsConstants.xpOffset] as int? ?? 0;
        final analyticsRoomId =
            value[AnalyticsConstants.analyticsRoomId] as String?;

        languageAnalytics[key] = LanguageAnalyticsProfileEntry(
          existing == null
              ? level
              : (level > existing.level ? level : existing.level),
          existing == null
              ? xpOffset
              : (xpOffset > existing.xpOffset ? xpOffset : existing.xpOffset),
          analyticsRoomId: analyticsRoomId ?? existing?.analyticsRoomId,
        );
      }
    }

    return AnalyticsProfileModel(
      baseLanguage: profileJson[ModelKey.sourceLanguage] != null
          ? _shortCode(profileJson[ModelKey.sourceLanguage] as String)
          : null,
      targetLanguage: profileJson[ModelKey.targetLanguage] != null
          ? _shortCode(profileJson[ModelKey.targetLanguage] as String)
          : null,
      languageAnalytics: languageAnalytics,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (targetLanguage != null) {
      json[ModelKey.targetLanguage] = targetLanguage;
    }

    if (baseLanguage != null) {
      json[ModelKey.sourceLanguage] = baseLanguage;
    }

    final analytics = {};
    if (languageAnalytics != null && languageAnalytics!.isNotEmpty) {
      for (final entry in languageAnalytics!.entries) {
        analytics[entry.key] = {
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

  String? analyticsRoomIdByLanguage(String langCode) =>
      languageAnalytics?[_shortCode(langCode)]?.analyticsRoomId;

  /// Records [level] and [analyticsRoomId] for [langCode]'s language.
  ///
  /// The level is set, not raised: it legitimately falls when a learner blocks
  /// constructs (analytics-system.instructions.md, "Blocking Constructs").
  ///
  /// A null [analyticsRoomId] means "not known here" — the room may simply not
  /// have surfaced in sync yet — and leaves any id already recorded alone.
  /// Instructor analytics access is granted through that id, so losing it costs
  /// a student's instructors their access; only
  /// [clearForeignAnalyticsRoomIds] removes one, and only for a room this user
  /// demonstrably does not own.
  void setLanguageInfo(String langCode, int level, String? analyticsRoomId) {
    final key = _shortCode(langCode);
    final entry = (languageAnalytics ??= {})[key] ??=
        LanguageAnalyticsProfileEntry(0, 0);

    entry.level = level;
    if (analyticsRoomId != null) entry.analyticsRoomId = analyticsRoomId;
  }

  /// Forgets every analytics room id naming a room outside [ownRoomIds] — the
  /// entry's level is kept, since only the room id's owner is knowable here.
  void clearForeignAnalyticsRoomIds(Set<String> ownRoomIds) {
    final entries = languageAnalytics?.values;
    if (entries == null) return;
    for (final entry in entries) {
      final roomId = entry.analyticsRoomId;
      if (roomId != null && !ownRoomIds.contains(roomId)) {
        entry.analyticsRoomId = null;
      }
    }
  }

  void addXPOffset(String langCode, int xpOffset, String? analyticsRoomId) {
    final key = _shortCode(langCode);
    final entry = (languageAnalytics ??= {})[key] ??=
        LanguageAnalyticsProfileEntry(0, 0);

    entry.analyticsRoomId ??= analyticsRoomId;
    entry.xpOffset += xpOffset;
  }

  int? get level =>
      targetLanguage == null ? null : languageAnalytics?[targetLanguage]?.level;

  int? get xpOffset => targetLanguage == null
      ? null
      : languageAnalytics?[targetLanguage]?.xpOffset;

  int? xpOffsetByLanguage(String langCode) =>
      languageAnalytics?[_shortCode(langCode)]?.xpOffset;

  /// [targetLanguage] / [baseLanguage] resolved for display (flag, name).
  /// Resolved on read rather than at parse time so that a language list which
  /// has not loaded yet costs a flag, never a dropped entry.
  LanguageModel? get targetLanguageModel => targetLanguage == null
      ? null
      : PLanguageStore.byLangCode(targetLanguage!);

  LanguageModel? get baseLanguageModel =>
      baseLanguage == null ? null : PLanguageStore.byLangCode(baseLanguage!);

  /// This language's entry, for a UI row showing [language]'s level. Every
  /// regional variant resolves to the one entry its language shares.
  LanguageAnalyticsProfileEntry? entryFor(LanguageModel language) =>
      languageAnalytics?[language.langCodeShort];
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

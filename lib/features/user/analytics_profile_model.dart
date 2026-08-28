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
  ///
  /// Normalized on assignment: the short-code grain is the whole point of this
  /// class, and a full code stored here reads back as a missing entry — which
  /// is exactly the bug #8582 fixed. Enforcing it in the setter rather than
  /// trusting every caller means it cannot be reintroduced by construction.
  String? get baseLanguage => _baseLanguage;
  set baseLanguage(String? code) =>
      _baseLanguage = code == null ? null : _shortCode(code);
  String? _baseLanguage;

  String? get targetLanguage => _targetLanguage;
  set targetLanguage(String? code) =>
      _targetLanguage = code == null ? null : _shortCode(code);
  String? _targetLanguage;

  Map<String, LanguageAnalyticsProfileEntry>? languageAnalytics;

  AnalyticsProfileModel({
    String? baseLanguage,
    String? targetLanguage,
    this.languageAnalytics,
  }) {
    this.baseLanguage = baseLanguage;
    this.targetLanguage = targetLanguage;
  }

  static String _shortCode(String langCode) => langCode.split('-').first;

  factory AnalyticsProfileModel.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey(PangeaEventTypes.profileAnalytics)) {
      return AnalyticsProfileModel();
    }

    final profileJson = json[PangeaEventTypes.profileAnalytics];

    // Profiles written before #8582 carry a key per locale over one shared set
    // of analytics. Group the variants, then reduce each group deterministically
    // — iterating the decoded map directly would make the result depend on the
    // server's key order.
    final byLanguage = <String, List<MapEntry<String, Map>>>{};
    final analyticsJson = profileJson[AnalyticsConstants.analytics];
    if (analyticsJson is Map) {
      for (final entry in analyticsJson.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! Map) continue;
        (byLanguage[_shortCode(key)] ??= []).add(MapEntry(key, value));
      }
    }

    final languageAnalytics = <String, LanguageAnalyticsProfileEntry>{};
    for (final group in byLanguage.entries) {
      final language = group.key;
      final variants = group.value..sort((a, b) => a.key.compareTo(b.key));

      var level = 0;
      var xpOffset = 0;
      var stars = 0;
      String? analyticsRoomId;
      for (final variant in variants) {
        final v = variant.value;
        final variantLevel = v[AnalyticsConstants.level];
        final variantOffset = v[AnalyticsConstants.xpOffset];
        if (variantLevel is int && variantLevel > level) level = variantLevel;
        // Largest, not sum. The offset exists so a level never visibly drops
        // (analytics-system.instructions.md, "Level Protection"); the largest
        // any variant recorded is the highest level this learner was ever
        // protected at, which is the guarantee being preserved. Summing would
        // publish a level higher than any they actually saw.
        if (variantOffset is int && variantOffset > xpOffset) {
          xpOffset = variantOffset;
        }
        // Largest for the same reason the published total only ever rises:
        // a smaller number is never evidence the larger one is wrong.
        final variantStars = v[AnalyticsConstants.stars];
        if (variantStars is int && variantStars > stars) stars = variantStars;
        // The exact short-code key wins; otherwise the first variant to name a
        // room, in sorted key order. Any id is provisional anyway —
        // [clearForeignAnalyticsRoomIds] drops one this user does not own and
        // the analytics-room backfill re-derives it from live rooms.
        final variantRoomId = v[AnalyticsConstants.analyticsRoomId];
        if (variantRoomId is String && variantRoomId.isNotEmpty) {
          if (variant.key == language || analyticsRoomId == null) {
            analyticsRoomId = variantRoomId;
          }
        }
      }

      languageAnalytics[language] = LanguageAnalyticsProfileEntry(
        level,
        xpOffset,
        analyticsRoomId: analyticsRoomId,
        stars: stars,
      );
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
          if (entry.value.stars > 0)
            AnalyticsConstants.stars: entry.value.stars,
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

  int? xpOffsetByLanguage(String langCode) =>
      languageAnalytics?[_shortCode(langCode)]?.xpOffset;

  /// Raises [langCode]'s banked star total to [stars], reporting whether that
  /// changed anything (nothing is published when it did not).
  ///
  /// Raised, never set. Unlike a level, which legitimately falls when a learner
  /// blocks constructs, every way a star count can be wrong makes it too LOW —
  /// a device part-way through its first sync is missing rooms, and a session's
  /// language only arrives once its activity plan has been fetched — so a
  /// smaller number is never evidence the published one is wrong. See
  /// profile.instructions.md.
  bool raiseStars(String langCode, int stars) {
    final key = _shortCode(langCode);
    final entry = (languageAnalytics ??= {})[key] ??=
        LanguageAnalyticsProfileEntry(0, 0);

    if (stars <= entry.stars) return false;
    entry.stars = stars;
    return true;
  }

  int? starsByLanguage(String langCode) =>
      languageAnalytics?[_shortCode(langCode)]?.stars;

  int? levelByLanguage(String langCode) =>
      languageAnalytics?[_shortCode(langCode)]?.level;

  /// This language's entry, for a row that displays a level — null for a
  /// regional variant even when its language has analytics.
  ///
  /// Variants (`fr-CA`, `es-MX`) are legacy rows over one shared set of
  /// analytics: there is one analytics room and one local partition per
  /// language, so a level shown against each variant reads as separate
  /// progress the learner does not have. The level belongs to the language, so
  /// only the language's own row carries it (#8582). Every multi-variant
  /// language in the target list has such a row, so no level is hidden by this.
  LanguageAnalyticsProfileEntry? displayEntryFor(LanguageModel language) =>
      language.isLocalized ? null : languageAnalytics?[language.langCodeShort];

  /// [targetLanguage] / [baseLanguage] resolved for display (flag, name).
  /// Resolved on read rather than at parse time so that a language list which
  /// has not loaded yet costs a flag, never a dropped entry.
  LanguageModel? get targetLanguageModel => targetLanguage == null
      ? null
      : PLanguageStore.byLangCode(targetLanguage!);

  LanguageModel? get baseLanguageModel =>
      baseLanguage == null ? null : PLanguageStore.byLangCode(baseLanguage!);
}

class LanguageAnalyticsProfileEntry {
  int level;
  int xpOffset = 0;
  String? analyticsRoomId;

  /// Banked stars in this language — see [AnalyticsProfileModel.raiseStars].
  int stars;

  LanguageAnalyticsProfileEntry(
    this.level,
    this.xpOffset, {
    this.analyticsRoomId,
    this.stars = 0,
  });
}

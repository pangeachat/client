import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The party-size filter: how many roles the activity is designed for
/// (world-map.instructions.md, "Filters"). Filters on the pin's thin
/// [QuestActivityCard.roleCount]; an unknown role count is kept (permissive,
/// mirroring the "unknown level: keep" rule).
enum MapPartySize {
  two,
  three,
  fourPlus;

  bool matches(int? roleCount) {
    if (roleCount == null) return true;
    switch (this) {
      case MapPartySize.two:
        return roleCount == 2;
      case MapPartySize.three:
        return roleCount == 3;
      case MapPartySize.fourPlus:
        return roleCount >= 4;
    }
  }
}

/// Sentinel for [WorldMapFilter.copyWith] so a nullable field can be explicitly
/// cleared to null (passing the sentinel means "leave unchanged").
const Object _unset = Object();

class WorldMapFilter {
  final String query;

  /// The learner's target language, driven by their **settings** (not a map
  /// pill):
  final LanguageModel? l2;
  final Set<LanguageLevelTypeEnum> cefrFilter;
  final Set<LanguageLevelTypeEnum> defaultCefr;

  /// The party-size filter, or null for "All players" (the default).
  final MapPartySize? partySize;

  /// The status filter — matched against the activity's resolved
  /// [ActivityPinState] — or null for "All statuses" (the default). The five
  /// statuses map 1:1 to the pin states: Available→available, Ongoing→
  /// ongoingActive, Open to Join→joinable, Waiting→ongoingPending, Completed→
  /// inProgress (world-map.instructions.md, "Filters").
  final ActivityPinState? status;

  final bool filterDefaultsApplied;

  const WorldMapFilter({
    this.query = '',
    this.l2,
    this.cefrFilter = const {},
    this.defaultCefr = const {},
    this.partySize,
    this.status,
    this.filterDefaultsApplied = false,
  });

  /// The single selected CEFR level, or null for "All levels". [cefrFilter]
  LanguageLevelTypeEnum? get cefrLevel =>
      cefrFilter.isEmpty ? null : cefrFilter.first;

  bool get canReset =>
      query.isNotEmpty ||
      partySize != null ||
      status != null ||
      cefrFilter.length != defaultCefr.length ||
      !cefrFilter.containsAll(defaultCefr);

  /// How many filter categories are narrowed off their "All" state — the count
  /// shown on the collapsed mobile filter button's badge. Derived from the live
  /// fields (not a hardcoded maximum) so adding a category extends it for free.
  /// The free-text [query] is search, not one of the pills, so it is excluded.
  int get activeFilterCount {
    var count = 0;
    if (cefrFilter.isNotEmpty) count++;
    if (partySize != null) count++;
    if (status != null) count++;
    return count;
  }

  WorldMapFilter copyWith({
    String? query,
    LanguageModel? l2,
    Set<LanguageLevelTypeEnum>? cefrFilter,
    Set<LanguageLevelTypeEnum>? defaultCefr,
    Object? partySize = _unset,
    Object? status = _unset,
    bool? filterDefaultsApplied,
  }) => WorldMapFilter(
    query: query ?? this.query,
    l2: l2 ?? this.l2,
    cefrFilter: cefrFilter ?? this.cefrFilter,
    defaultCefr: defaultCefr ?? this.defaultCefr,
    partySize: identical(partySize, _unset)
        ? this.partySize
        : partySize as MapPartySize?,
    status: identical(status, _unset)
        ? this.status
        : status as ActivityPinState?,
    filterDefaultsApplied: filterDefaultsApplied ?? this.filterDefaultsApplied,
  );

  Map<String, dynamic> toJson() => {
    "query": query,
    "l2": l2?.toJson(),
    "cefr_filter": cefrFilter.toList(),
    "default_cefr": defaultCefr.toList(),
    "party_size": partySize?.name,
    "status": status?.name,
    "filter_defaults_applied": filterDefaultsApplied,
  };
}

class WorldMapFilterState {
  WorldMapFilter _filter = WorldMapFilter();

  WorldMapFilter get filter => _filter;

  bool include(QuestActivityCard card, ActivityPinState state) {
    return _langMatches(card) &&
        _cefrMatches(card) &&
        _partyMatches(card) &&
        _statusMatches(state) &&
        card.matchesQuery(_filter.query);
  }

  bool _langMatches(QuestActivityCard card) {
    final filterL2 = _filter.l2;
    if (filterL2 == null) return true;
    final l2 = card.l2;
    return filterL2.langCodeShort == l2.split('-').first;
  }

  bool _cefrMatches(QuestActivityCard card) {
    if (_filter.cefrFilter.isEmpty) return true; // "All levels"
    final cefr = card.cefr;
    if (cefr == null || cefr.isEmpty) return true; // unknown level: keep
    final norm = cefr.toUpperCase().replaceAll('_', '');
    return _filter.cefrFilter.any((l) => l.string == norm);
  }

  bool _partyMatches(QuestActivityCard card) {
    final p = _filter.partySize;
    return p == null || p.matches(card.roleCount);
  }

  bool _statusMatches(ActivityPinState state) {
    final s = _filter.status;
    return s == null || s == state;
  }

  bool applyDefaults({
    required LanguageLevelTypeEnum? cefrLevel,
    required LanguageModel? l2,
  }) {
    if (_filter.filterDefaultsApplied) return false;

    final defaultCefr = cefrLevel == null
        ? <LanguageLevelTypeEnum>{}
        : {cefrLevel};
    _filter = _filter.copyWith(
      filterDefaultsApplied: true,
      defaultCefr: defaultCefr,
      cefrFilter: {...defaultCefr},
      l2: l2,
    );
    return true;
  }

  void setQuery(String q) => _filter = _filter.copyWith(query: q);

  void setL2(LanguageModel? l2) => _filter = _filter.copyWith(l2: l2);

  /// Set the Level pill: null clears it to "All levels"; otherwise filter to
  /// exactly [level].
  void setCefrLevel(LanguageLevelTypeEnum? level) {
    _filter = _filter.copyWith(
      cefrFilter: level == null ? <LanguageLevelTypeEnum>{} : {level},
    );
  }

  /// A settings-driven CEFR change: reset BOTH the personalized default and the
  /// current level to exactly [level] (or "All levels" when null).
  void setDefaultCefrLevel(LanguageLevelTypeEnum? level) {
    final def = level == null ? <LanguageLevelTypeEnum>{} : {level};
    _filter = _filter.copyWith(defaultCefr: def, cefrFilter: {...def});
  }

  void setPartySize(MapPartySize? p) =>
      _filter = _filter.copyWith(partySize: p);

  void setStatus(ActivityPinState? s) => _filter = _filter.copyWith(status: s);

  void resetFilters() {
    _filter = _filter.copyWith(
      query: '',
      partySize: null,
      status: null,
      cefrFilter: {..._filter.defaultCefr},
    );
  }
}

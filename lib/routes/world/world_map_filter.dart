import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';

class WorldMapFilter {
  final String query;
  final bool l2Only;
  final LanguageModel? l2;
  final Set<LanguageLevelTypeEnum> cefrFilter;
  final Set<LanguageLevelTypeEnum> defaultCefr;
  final Set<MapCompletionFilter> completionFilter;
  final bool filterDefaultsApplied;

  const WorldMapFilter({
    this.query = '',
    this.l2Only = true,
    this.l2,
    this.cefrFilter = const {},
    this.defaultCefr = const {},
    this.completionFilter = const {},
    this.filterDefaultsApplied = false,
  });

  bool get canReset =>
      query.isNotEmpty ||
      !l2Only ||
      completionFilter.isNotEmpty ||
      cefrFilter.length != defaultCefr.length ||
      !cefrFilter.containsAll(defaultCefr);

  WorldMapFilter copyWith({
    String? query,
    bool? l2Only,
    LanguageModel? l2,
    Set<LanguageLevelTypeEnum>? cefrFilter,
    Set<LanguageLevelTypeEnum>? defaultCefr,
    Set<MapCompletionFilter>? completionFilter,
    bool? filterDefaultsApplied,
  }) => WorldMapFilter(
    query: query ?? this.query,
    l2Only: l2Only ?? this.l2Only,
    l2: l2 ?? this.l2,
    cefrFilter: cefrFilter ?? this.cefrFilter,
    defaultCefr: defaultCefr ?? this.defaultCefr,
    completionFilter: completionFilter ?? this.completionFilter,
    filterDefaultsApplied: filterDefaultsApplied ?? this.filterDefaultsApplied,
  );

  Map<String, dynamic> toJson() => {
    "query": query,
    "l2_only": l2Only,
    "l2": l2?.toJson(),
    "cefr_filter": cefrFilter.toList(),
    "default_cefr": defaultCefr.toList(),
    "completion_filters": completionFilter.toList(),
    "filter_defaults_applied": filterDefaultsApplied,
  };
}

class WorldMapFilterState {
  WorldMapFilter _filter = WorldMapFilter();

  WorldMapFilter get filter => _filter;

  bool include(QuestActivityCard card, MapCompletionFilter status) {
    return _langMatches(card) &&
        _cefrMatches(card) &&
        _completionMatches(status) &&
        card.matchesQuery(_filter.query);
  }

  bool _langMatches(QuestActivityCard card) {
    final filterL2 = _filter.l2;
    if (!_filter.l2Only || filterL2 == null) return true;
    final l2 = card.l2;
    return filterL2.langCodeShort == l2.split('-').first;
  }

  bool _cefrMatches(QuestActivityCard card) {
    final cefr = card.cefr;
    if (cefr == null || cefr.isEmpty) return true; // unknown level: keep
    final norm = cefr.toUpperCase().replaceAll('_', '');
    return _filter.cefrFilter.any((l) => l.string == norm);
  }

  bool _completionMatches(MapCompletionFilter status) {
    return _filter.completionFilter.isEmpty ||
        _filter.completionFilter.contains(status);
  }

  bool applyDefaults({
    required LanguageLevelTypeEnum? cefrLevel,
    required LanguageModel? l2,
  }) {
    if (_filter.filterDefaultsApplied) return false;

    final filterDefaultsApplied = true;
    final defaultCefr = LanguageLevelTypeEnum.bandAtOrBelow(cefrLevel);
    final cefrFilter = {...defaultCefr};
    _filter = _filter.copyWith(
      filterDefaultsApplied: filterDefaultsApplied,
      defaultCefr: defaultCefr,
      cefrFilter: cefrFilter,
      l2: l2,
    );
    return true;
  }

  void setQuery(String q) => _filter = _filter.copyWith(query: q);

  void setL2(LanguageModel? l2) => _filter = _filter.copyWith(l2: l2);

  void setCefrLevel(LanguageLevelTypeEnum? cefrLevel) {
    final defaultCefr = LanguageLevelTypeEnum.bandAtOrBelow(cefrLevel);
    final cefrFilter = {...defaultCefr};
    _filter = _filter.copyWith(
      defaultCefr: defaultCefr,
      cefrFilter: cefrFilter,
    );
  }

  void toggleL2() => _filter = _filter.copyWith(l2Only: !_filter.l2Only);

  void toggleCefr(LanguageLevelTypeEnum level) {
    final updated = {..._filter.cefrFilter};
    updated.contains(level) ? updated.remove(level) : updated.add(level);
    _filter = _filter.copyWith(cefrFilter: updated);
  }

  void toggleCompletion(MapCompletionFilter c) {
    final updated = {..._filter.completionFilter};
    updated.contains(c) ? updated.remove(c) : updated.add(c);
    _filter = _filter.copyWith(completionFilter: updated);
  }

  void resetFilters({bool l2Only = true}) {
    _filter = _filter.copyWith(
      query: '',
      completionFilter: {},
      cefrFilter: {..._filter.defaultCefr},
      l2Only: l2Only,
    );
  }
}

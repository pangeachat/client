import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// Why the world map's view shows no matches — the empty-view card's verdict
/// ([WorldMapEmptyViewCard]), computed by the controller so both layouts read
/// one diagnosis. The cases are mutually exclusive by construction (checked in
/// this order) and each carries exactly the remedy that actually fixes it:
/// off-screen matches → zoom out; pill-excluded matches → widen the search;
/// a query matching nothing → no remedy pretends to help.
enum MapEmptyVerdict {
  /// Matches are visible (or the verdict doesn't apply — loading, camera not
  /// laid out): no card.
  none,

  /// Matches pass the filters/query but every one sits OUTSIDE the current
  /// viewport — zooming out reveals them.
  matchesOffscreen,

  /// Nothing passes anywhere loaded, but clearing the pills would surface
  /// matches — widening the search fixes it (and if those matches then sit
  /// off-screen, the verdict chains to [matchesOffscreen]).
  filtersHideMatches,

  /// The query matches nothing at all, even ignoring the pills.
  noSearchMatches,

  /// No query and nothing loaded at all.
  noActivities,
}

/// Sentinel for [WorldMapFilter.copyWith] so a nullable field can be explicitly
/// cleared to null (passing the sentinel means "leave unchanged").
const Object _unset = Object();

class WorldMapFilter {
  final String query;

  /// The learner's target language, driven by their **settings** (not a map
  /// pill):
  final LanguageModel? l2;

  /// The CEFR level filter, or empty for "All levels" (the default). No pill
  /// is pre-seeded: every filter starts at "All" so the map narrows nothing
  /// until the learner picks a value (world-map.instructions.md, "Filters").
  final Set<LanguageLevelTypeEnum> cefrFilter;

  /// The party-size filter: the activity's **designed role count** to match
  /// exactly, or null for "All players" (the default). One of
  /// [partySizeOptions] — activities top out at 5 roles (world-map.instructions.md,
  /// "Filters").
  final int? partySize;
  static const List<int> partySizeOptions = [2, 3, 4, 5];

  /// The status filter — matched against the activity's resolved
  /// [ActivityPinState] — or null for "All statuses" (the default). The five
  /// statuses map 1:1 to the pin states: Available→available, Ongoing→
  /// ongoingActive, Open to Join→joinable, Waiting→ongoingPending, Completed→
  /// inProgress (world-map.instructions.md, "Filters").
  final ActivityPinState? status;

  /// The level actually being matched when the learner's chosen level carries
  /// no content — the nearest one that does ([LanguageLevelTypeEnum.nearestTo]),
  /// resolved over the loaded set by [WorldMapFilterState.resolveCefrFallback].
  /// Null whenever the chosen level is being honoured exactly, which is the
  /// normal case; non-null is the map's cue to SAY it is showing a neighbouring
  /// level (world-map.instructions.md, "Empty levels fall back to the nearest
  /// one with content").
  final LanguageLevelTypeEnum? cefrFallback;

  final bool filterDefaultsApplied;

  const WorldMapFilter({
    this.query = '',
    this.l2,
    this.cefrFilter = const {},
    this.partySize,
    this.status,
    this.cefrFallback,
    this.filterDefaultsApplied = false,
  });

  /// The single selected CEFR level, or null for "All levels". [cefrFilter]
  LanguageLevelTypeEnum? get cefrLevel =>
      cefrFilter.isEmpty ? null : cefrFilter.first;

  /// The level the map is actually matching on: the learner's choice, or the
  /// [cefrFallback] standing in for it when that choice has no content. Null
  /// means "All levels" — no level term at all.
  LanguageLevelTypeEnum? get effectiveCefrLevel => cefrFallback ?? cefrLevel;

  /// Every pill defaults to "All", so any non-empty pill (or query) means the
  /// learner has narrowed away from the default — the reset control shows.
  bool get canReset =>
      query.isNotEmpty ||
      partySize != null ||
      status != null ||
      cefrFilter.isNotEmpty;

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
    Object? partySize = _unset,
    Object? status = _unset,
    Object? cefrFallback = _unset,
    bool? filterDefaultsApplied,
  }) => WorldMapFilter(
    query: query ?? this.query,
    l2: l2 ?? this.l2,
    cefrFilter: cefrFilter ?? this.cefrFilter,
    partySize: identical(partySize, _unset)
        ? this.partySize
        : partySize as int?,
    status: identical(status, _unset)
        ? this.status
        : status as ActivityPinState?,
    cefrFallback: identical(cefrFallback, _unset)
        ? this.cefrFallback
        : cefrFallback as LanguageLevelTypeEnum?,
    filterDefaultsApplied: filterDefaultsApplied ?? this.filterDefaultsApplied,
  );

  Map<String, dynamic> toJson() => {
    "query": query,
    "l2": l2?.toJson(),
    "cefr_filter": cefrFilter.toList(),
    "party_size": partySize,
    "status": status?.name,
    "cefr_fallback": cefrFallback?.string,
    "filter_defaults_applied": filterDefaultsApplied,
  };
}

class WorldMapFilterState {
  WorldMapFilter _filter = WorldMapFilter();

  WorldMapFilter get filter => _filter;

  /// [applyLanguage] carries the settings-fixed language constant, and is the
  /// one part of the filter set that differs by map scope. The WORLD map
  /// always applies it. A COURSE-scoped map does not: its pins are fetched at
  /// the COURSE's own L2 ([WorldMapPinsManager.loadCourseScopedPins]), so
  /// narrowing them by the learner's *settings* L2 would empty the map of any
  /// course taught in another language — with no lever to widen, since
  /// language is deliberately not one. The course scope is itself the
  /// narrowing there; the pills and the query still apply (#7716).
  bool include(
    QuestActivityCard card,
    ActivityPinState state, {
    bool applyLanguage = true,
  }) {
    return (!applyLanguage || _langMatches(card)) &&
        _cefrMatches(card) &&
        _partyMatches(card) &&
        _statusMatches(state) &&
        card.matchesQuery(_filter.query);
  }

  /// Language + query only — the "would clearing every pill surface matches?"
  /// probe behind [MapEmptyVerdict.filtersHideMatches]. Language stays applied
  /// (it is settings-fixed, not a pill the learner can widen in-app) wherever
  /// [include] applies it — see [applyLanguage] there.
  bool matchesIgnoringPills(
    QuestActivityCard card, {
    bool applyLanguage = true,
  }) =>
      (!applyLanguage || _langMatches(card)) &&
      card.matchesQuery(_filter.query);

  bool _langMatches(QuestActivityCard card) {
    final filterL2 = _filter.l2;
    if (filterL2 == null) return true;
    final l2 = card.l2;
    return filterL2.langCodeShort == l2.split('-').first;
  }

  bool _cefrMatches(QuestActivityCard card) {
    // The EFFECTIVE level, not the chosen one: when the chosen level carries no
    // content the map matches its nearest neighbour instead and says so
    // ([WorldMapFilter.cefrFallback], resolved by [resolveCefrFallback]).
    final level = _filter.effectiveCefrLevel;
    if (level == null) return true; // "All levels"
    final cefr = card.cefr;
    if (cefr == null || cefr.isEmpty) return true; // unknown level: keep
    return level.string == _normalizeCefr(cefr);
  }

  static String _normalizeCefr(String cefr) =>
      cefr.toUpperCase().replaceAll('_', '').replaceAll('-', '');

  bool _partyMatches(QuestActivityCard card) {
    final p = _filter.partySize;
    // Unknown role count is kept (permissive, mirroring "unknown level: keep").
    return p == null || card.roleCount == null || card.roleCount == p;
  }

  bool _statusMatches(ActivityPinState state) {
    final s = _filter.status;
    return s == null || s == state;
  }

  /// Seed the one settings-fixed filter — the learner's target language —
  /// exactly once. The three pills (Level, Party, Status) are deliberately NOT
  /// pre-seeded: they all start at "All", so the map narrows only by language
  /// until the learner picks a pill (world-map.instructions.md, "Filters").
  bool applyDefaults({required LanguageModel? l2}) {
    if (_filter.filterDefaultsApplied) return false;
    _filter = _filter.copyWith(filterDefaultsApplied: true, l2: l2);
    return true;
  }

  void setQuery(String q) => _filter = _filter.copyWith(query: q);

  void setL2(LanguageModel? l2) => _filter = _filter.copyWith(l2: l2);

  /// Set the Level pill: null clears it to "All levels"; otherwise filter to
  /// exactly [level].
  void setCefrLevel(LanguageLevelTypeEnum? level) {
    _filter = _filter.copyWith(
      cefrFilter: level == null ? <LanguageLevelTypeEnum>{} : {level},
      // A fresh choice is honoured exactly until the loaded set says otherwise
      // — the controller re-resolves right after this.
      cefrFallback: null,
    );
  }

  /// Resolve the Level pill's fallback against [candidates] — the loaded,
  /// renderable pins that pass everything EXCEPT the level term
  /// ([matchesIgnoringPills] plus a coordinate, so the promise can only name a
  /// level the learner can actually see).
  ///
  /// The chosen level stands when any candidate carries it (or carries no level
  /// at all, which [_cefrMatches] keeps); otherwise the nearest level with
  /// content stands in for it and [WorldMapFilter.cefrFallback] records the
  /// substitution for the map to display. Returns true when the resolution
  /// changed, so the caller can skip a needless rebuild.
  bool resolveCefrFallback(Iterable<QuestActivityCard> candidates) {
    final chosen = _filter.cefrLevel;
    final previous = _filter.cefrFallback;

    LanguageLevelTypeEnum? resolved;
    if (chosen != null) {
      final available = <LanguageLevelTypeEnum>{};
      var hasUnleveled = false;
      for (final card in candidates) {
        final cefr = card.cefr;
        if (cefr == null || cefr.isEmpty) {
          hasUnleveled = true;
          break; // an unleveled card already satisfies any chosen level
        }
        // Matched against the known codes rather than parsed:
        // LanguageLevelTypeEnum.fromString falls back to A1 for anything it
        // doesn't recognise, which would let a garbage level silently satisfy
        // an A1 choice. An unrecognised code contributes nothing instead.
        final norm = _normalizeCefr(cefr);
        for (final level in LanguageLevelTypeEnum.values) {
          if (level.string == norm) available.add(level);
        }
      }
      if (!hasUnleveled) {
        resolved = LanguageLevelTypeEnum.nearestTo(chosen, available);
      }
    }

    if (resolved == previous) return false;
    _filter = _filter.copyWith(cefrFallback: resolved);
    return true;
  }

  void setPartySize(int? p) => _filter = _filter.copyWith(partySize: p);

  void setStatus(ActivityPinState? s) => _filter = _filter.copyWith(status: s);

  /// Restore every pill to its default — "All" across the board — and clear the
  /// query. Language is settings-fixed and untouched.
  void resetFilters() {
    _filter = _filter.copyWith(
      query: '',
      partySize: null,
      status: null,
      cefrFilter: const {},
      cefrFallback: null,
    );
  }
}

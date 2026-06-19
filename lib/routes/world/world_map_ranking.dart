import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// The displayed state of a world-map activity pin. Resolved highest-wins from
/// the ladder below (see world-map.instructions.md). `locked` is defined for
/// completeness but not produced yet — it needs client-hydrated progression
/// rules, so a not-yet-started activity reads as `unlocked` for now.
enum ActivityPinState { locked, unlocked, completed, joinable }

/// The visual weight a pin renders at, assigned by the ranking + state gate.
enum PinTier { small, mid, large }

/// Live signals for one activity, derived from Matrix room state (not on the
/// pin card): its resolved [state], whether an open session has been [pinged]
/// to the course, and a 0..1 [recency] (newest open session first).
class PinSignals {
  final ActivityPinState state;
  final bool pinged;
  final double recency;
  const PinSignals({
    this.state = ActivityPinState.unlocked,
    this.pinged = false,
    this.recency = 0,
  });
}

/// The ranking outcome for the pins currently in view. [largePool] is the
/// ordered set of joinable activities eligible for the large featured card — the
/// display shows up to its budget at a time and rotates through the rest, and
/// any pool member not currently featured renders at mid weight. [midIds] are
/// the non-joinable activities promoted to mid weight; everything else is small.
class RankingResult {
  final List<String> largePool;
  final Set<String> midIds;
  const RankingResult({required this.largePool, required this.midIds});
}

/// The relevance band for a pin (the dominant, well-separated term in the
/// score): joined-course objective `3` > level-appropriate L2 objective `2` >
/// in-L2 `1` > global `0`. See the Priority matrix in world-map.instructions.md.
int relevanceBand(
  QuestActivityCard pin, {
  required String? userL2,
  required LanguageLevelTypeEnum? userCefr,
  required Set<String> joinedObjectiveIds,
}) {
  // A joined-course objective wins outright (these are in the user's L2 anyway).
  if (joinedObjectiveIds.isNotEmpty &&
      pin.learningObjectiveRefs.any(joinedObjectiveIds.contains)) {
    return 3;
  }
  // Not in my L2 → global. (When the user has no L2 set, nothing is "foreign".)
  final isGlobal = userL2 != null && pin.l2.isNotEmpty && pin.l2 != userL2;
  if (isGlobal) return 0;
  // In my L2: level-appropriate + objective-bearing earns band 2, else band 1.
  final levelOk = _cefrAtOrBelow(pin.cefr, userCefr);
  if (levelOk && pin.learningObjectiveRefs.isNotEmpty) return 2;
  return 1;
}

bool _cefrAtOrBelow(String? cefr, LanguageLevelTypeEnum? userCefr) {
  if (userCefr == null) return true; // no CEFR set → no narrowing
  if (cefr == null || cefr.isEmpty) {
    return true; // unknown level → don't exclude
  }
  return LanguageLevelTypeEnum.fromString(cefr).storageInt <=
      userCefr.storageInt;
}

/// score = relevance_band + 0.6·pinged + 0.3·recency. The boosts sum to at most
/// 0.9 (< one band step), so they only reorder within a band.
double pinScore(int band, PinSignals s) =>
    band + 0.6 * (s.pinged ? 1 : 0) + 0.3 * s.recency.clamp(0.0, 1.0);

class _Scored {
  final QuestActivityCard pin;
  final double score;
  final ActivityPinState state;
  const _Scored(this.pin, this.score, this.state);
}

/// Rank the pins currently in view into the large pool and the mid set (the
/// caller filters to the active viewport and re-runs this on pan/zoom, so the
/// budgets are per-view). State acts as a hard gate: only joinable pins reach
/// the large pool; completed and locked are forced small (never promoted);
/// unlocked pins compete for the mid budget by score, with a per-objective
/// diversity cap so one objective can't monopolize the featured set.
RankingResult rankPins({
  required List<QuestActivityCard> inViewPins,
  required String? userL2,
  required LanguageLevelTypeEnum? userCefr,
  required Set<String> joinedObjectiveIds,
  required Map<String, PinSignals> signals,
  int midBudget = 10,
  int maxPerDiversityKey = 2,
}) {
  PinSignals sig(String id) => signals[id] ?? const PinSignals();

  final scored = inViewPins.map((p) {
    final band = relevanceBand(
      p,
      userL2: userL2,
      userCefr: userCefr,
      joinedObjectiveIds: joinedObjectiveIds,
    );
    final s = sig(p.activityId);
    return _Scored(p, pinScore(band, s), s.state);
  }).toList()..sort((a, b) => b.score.compareTo(a.score));

  final largePool = scored
      .where((e) => e.state == ActivityPinState.joinable)
      .map((e) => e.pin.activityId)
      .toList();

  final midIds = <String>{};
  final perKey = <String, int>{};
  for (final e in scored) {
    if (midIds.length >= midBudget) break;
    // Only unlocked pins compete for mid: joinable lives in largePool;
    // completed and locked are forced small.
    if (e.state != ActivityPinState.unlocked) continue;
    final key = e.pin.learningObjectiveRefs.isNotEmpty
        ? e.pin.learningObjectiveRefs.first
        : null;
    if (key != null) {
      final count = perKey[key] ?? 0;
      if (count >= maxPerDiversityKey) continue;
      perKey[key] = count + 1;
    }
    midIds.add(e.pin.activityId);
  }

  return RankingResult(largePool: largePool, midIds: midIds);
}

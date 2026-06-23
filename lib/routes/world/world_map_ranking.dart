import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// The displayed colour-state of a world-map activity pin, resolved highest-wins
/// from the ladder `locked < unlocked < joinable` (enum order; see
/// world-map.instructions.md). Completion is no longer a state — it renders as a
/// progress fill carried by [PinSignals.completionFraction], orthogonal to the
/// colour, so finished work stays visible without hiding the next thing to do.
enum ActivityPinState {
  locked,
  unlocked,
  joinable;

  /// The colour a pin reads as for its [ActivityPinState] (see
  /// world-map.instructions.md): locked gray, unlocked purple, joinable green.
  /// Completion is not a colour — it renders as the inner gold fill in [_stateDot].
  Color get color {
    switch (this) {
      case ActivityPinState.joinable:
        return const Color(0xFF34A853); // green — an open session to join
      case ActivityPinState.unlocked:
        return const Color(0xFF7B61FF); // purple — available, not started
      case ActivityPinState.locked:
        return Colors.grey;
    }
  }

  Color get accent {
    switch (this) {
      case ActivityPinState.joinable:
        return AppConfig.green;
      case ActivityPinState.locked:
        return AppConfig.gray;
      case ActivityPinState.unlocked:
        return AppConfig.purple;
    }
  }
}

/// The visual weight a pin renders at, assigned by the ranking + state gate.
enum PinTier {
  small,
  mid,
  large;

  double dotHeight(ActivityPinState state) => switch (this) {
    PinTier.small => 18.0,
    PinTier.mid => 44.0,
    PinTier.large => state == ActivityPinState.joinable ? 184.0 : 150.0,
  };

  double get dotWidth => switch (this) {
    PinTier.small => 18.0,
    PinTier.mid => 44.0,
    PinTier.large => 260.0,
  };
}

/// Live signals for one activity, derived from Matrix room state (not on the
/// pin card): its resolved [state], a 0..1 [completionFraction] (stars earned
/// toward the activity's total, drawn as the inner fill), whether an open
/// session has been [pinged] to the course, and a 0..1 [recency] (newest open
/// session first).
class PinSignals {
  final ActivityPinState state;
  final double completionFraction;
  final bool pinged;
  final double recency;
  const PinSignals({
    this.state = ActivityPinState.unlocked,
    this.completionFraction = 0,
    this.pinged = false,
    this.recency = 0,
  });
}

/// The ranking outcome for the pins currently in view. [largePool] is the
/// ordered set of activities eligible for the large featured card — open
/// joinable sessions and in-course unlocked activities (joinable featured
/// first). The display shows up to its budget at a time and rotates through the
/// rest, and any pool member not currently featured renders at mid weight.
/// [midIds] are the other unlocked activities promoted to mid weight; everything
/// else is small.
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
  final double fraction;
  final int band;
  const _Scored(this.pin, this.score, this.state, this.fraction, this.band);
}

/// Rank the pins currently in view into the large pool and the mid set (the
/// caller filters to the active viewport and re-runs this on pan/zoom, so the
/// budgets are per-view). State + relevance gate prominence: joinable sessions
/// and in-course unlocked activities (joined-course objective, not finished)
/// reach the large pool, joinable first; locked pins and finished activities
/// (full progress fill) are forced small (never promoted); the remaining
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
    return _Scored(p, pinScore(band, s), s.state, s.completionFraction, band);
  }).toList()..sort((a, b) => b.score.compareTo(a.score));

  // The large pool: open joinable sessions and in-course unlocked activities
  // (joined-course objective `band 3`, not yet finished). Joinable is featured
  // first — joining a live session is the goal; within each, higher score wins.
  final largePool =
      scored.where((e) {
        if (e.state == ActivityPinState.joinable) return true;
        return e.state == ActivityPinState.unlocked &&
            e.band >= 3 &&
            e.fraction < 1.0;
      }).toList()..sort((a, b) {
        final aJoin = a.state == ActivityPinState.joinable ? 0 : 1;
        final bJoin = b.state == ActivityPinState.joinable ? 0 : 1;
        if (aJoin != bJoin) return aJoin - bJoin;
        return b.score.compareTo(a.score);
      });
  final largeIds = largePool.map((e) => e.pin.activityId).toList();
  final largeSet = largeIds.toSet();

  final midIds = <String>{};
  final perKey = <String, int>{};
  for (final e in scored) {
    if (midIds.length >= midBudget) break;
    // Only not-yet-finished unlocked pins compete for mid: joinable lives in
    // largePool; locked pins and finished activities are forced small.
    if (e.state != ActivityPinState.unlocked) continue;
    if (e.fraction >= 1.0) continue;
    // A large-pool member (in-course unlocked) not currently featured already
    // renders mid via the pool, so it doesn't also consume the mid budget.
    if (largeSet.contains(e.pin.activityId)) continue;
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

  return RankingResult(largePool: largeIds, midIds: midIds);
}

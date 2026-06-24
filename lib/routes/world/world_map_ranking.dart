import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// The displayed colour-state of a world-map activity pin. There is no locked
/// state: progression only ranks, never gates (#7186). Completion is not a
/// state either — it renders as a progress fill carried by
/// [PinSignals.completionFraction], orthogonal to the colour. See
/// world-map.instructions.md.
enum ActivityPinState {
  unlocked,
  joinable;

  /// unlocked = purple (available), joinable = green (an open session to join).
  Color get color {
    switch (this) {
      case ActivityPinState.joinable:
        return const Color(0xFF34A853);
      case ActivityPinState.unlocked:
        return const Color(0xFF7B61FF);
    }
  }

  Color get accent {
    switch (this) {
      case ActivityPinState.joinable:
        return AppConfig.green;
      case ActivityPinState.unlocked:
        return AppConfig.purple;
    }
  }
}

/// The visual weight a pin renders at, filled from the top of the score.
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

/// Live signals for one activity, derived from Matrix room state: its colour
/// [state], a 0..1 [completionFraction] (stars earned toward the activity's
/// total, drawn as the inner fill; a full row demotes via the score but never
/// hides the pin), whether an open session has been [pinged], and a 0..1
/// [recency] (newest open session first).
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

/// The ranking outcome for the pins currently in view: the [largeIds] featured
/// at large weight (top of the score, capped at the large budget) and [midIds]
/// at mid weight; everything else is small. No rotation — a static top-N.
class RankingResult {
  final List<String> largeIds;
  final Set<String> midIds;
  const RankingResult({required this.largeIds, required this.midIds});
}

/// The relevance band (0..2) for a pin: the next-Mission gradient when the pin
/// sits in one of the learner's in-scope quests, else a plain L2/level-fit floor
/// kept below the in-quest gradient (foreign 0, in-L2 level-appropriate
/// objective-bearing 1.0, other in-L2 0.5). See world-map.instructions.md.
double relevanceBand(
  QuestActivityCard pin, {
  required String? userL2,
  required LanguageLevelTypeEnum? userCefr,
  required ProgressionResolution progression,
}) {
  final gradient = progression.missionGradient(pin.learningObjectiveRefs);
  if (gradient > 0) return gradient;
  final isGlobal = userL2 != null && pin.l2.isNotEmpty && pin.l2 != userL2;
  if (isGlobal) return 0;
  final levelOk = _cefrAtOrBelow(pin.cefr, userCefr);
  if (levelOk && pin.learningObjectiveRefs.isNotEmpty) return 1.0;
  return 0.5;
}

bool _cefrAtOrBelow(String? cefr, LanguageLevelTypeEnum? userCefr) {
  if (userCefr == null) return true;
  if (cefr == null || cefr.isEmpty) return true;
  return LanguageLevelTypeEnum.fromString(cefr).storageInt <=
      userCefr.storageInt;
}

/// score = 3*joinable + relevance_band + 0.6*pinged + 0.3*recency - 0.5*finished.
/// Joinable is the heaviest term (joining a live session is the map's goal); a
/// finished activity (full star row) demotes but stays visible.
double pinScore({required double band, required PinSignals s}) =>
    3 * (s.state == ActivityPinState.joinable ? 1 : 0) +
    band +
    0.6 * (s.pinged ? 1 : 0) +
    0.3 * s.recency.clamp(0.0, 1.0) -
    0.5 * (s.completionFraction >= 1.0 ? 1 : 0);

class _Scored {
  final QuestActivityCard pin;
  final double score;
  const _Scored(this.pin, this.score);
}

/// Rank the in-view pins into a static large set (top by score, up to
/// [largeBudget]) and a mid set (next, up to [midBudget]), with a per-objective
/// diversity cap across both so one objective can't monopolise the featured set.
/// Every pin competes — no state/lock gate; a finished pin is demoted by its
/// score, not excluded. The caller filters to the active viewport and re-runs on
/// pan/zoom, so the budgets are per-view.
RankingResult rankPins({
  required List<QuestActivityCard> inViewPins,
  required String? userL2,
  required LanguageLevelTypeEnum? userCefr,
  required ProgressionResolution progression,
  required Map<String, PinSignals> signals,
  int largeBudget = 3,
  int midBudget = 10,
  int maxPerDiversityKey = 2,
}) {
  PinSignals sig(String id) => signals[id] ?? const PinSignals();

  final scored = inViewPins.map((p) {
    final band = relevanceBand(
      p,
      userL2: userL2,
      userCefr: userCefr,
      progression: progression,
    );
    return _Scored(p, pinScore(band: band, s: sig(p.activityId)));
  }).toList()..sort((a, b) => b.score.compareTo(a.score));

  final largeIds = <String>[];
  final midIds = <String>{};
  final perKey = <String, int>{};
  for (final e in scored) {
    if (largeIds.length >= largeBudget && midIds.length >= midBudget) break;
    final refs = e.pin.learningObjectiveRefs;
    final key = refs.isNotEmpty ? refs.first : null;
    if (key != null && (perKey[key] ?? 0) >= maxPerDiversityKey) continue;
    if (largeIds.length < largeBudget) {
      largeIds.add(e.pin.activityId);
    } else {
      midIds.add(e.pin.activityId);
    }
    if (key != null) perKey[key] = (perKey[key] ?? 0) + 1;
  }

  return RankingResult(largeIds: largeIds, midIds: midIds);
}

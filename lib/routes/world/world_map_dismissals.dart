/// The learner's X-dismissals of large cards (#7207), with expiry (#7245
/// follow-up): a dismissal demotes the activity out of the large tier and adds
/// a small negative ranking weight ([kDismissedPenalty]) for [ttl], then lapses
/// — so an X is never a permanent burial. An activity that later earns real
/// attention (say a joinable session opens on it) comes back once the TTL
/// passes. Pure and clock-injected so the TTL arithmetic is unit-testable.
class WorldMapDismissals {
  /// How long an X keeps an activity out of the large tier. Long enough that
  /// the card doesn't bounce back mid-browse, short enough that a genuinely
  /// hot activity resurfaces within the same sitting.
  static const Duration ttl = Duration(minutes: 10);

  final Map<String, DateTime> _dismissedAt = {};

  void dismiss(String activityId, DateTime now) {
    _dismissedAt[activityId] = now;
  }

  /// The activity ids whose dismissal is still in force at [now]. Lapsed
  /// entries are pruned as a side effect so the map can't grow unbounded over
  /// a long-lived map instance.
  Set<String> activeIds(DateTime now) {
    _dismissedAt.removeWhere((_, at) => now.difference(at) >= ttl);
    return _dismissedAt.keys.toSet();
  }

  /// When the earliest active dismissal lapses (null if none are active) — the
  /// controller arms a timer for this instant so an idle map re-ranks and the
  /// card can return without waiting for the next pan/zoom/sync.
  DateTime? nextExpiry(DateTime now) {
    final active = activeIds(now);
    if (active.isEmpty) return null;
    final earliest = active
        .map((id) => _dismissedAt[id]!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return earliest.add(ttl);
  }
}

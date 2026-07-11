/// Abbreviates a tracker count for width-bounded display: counts above 999
/// render as `1.2k` / `12k` / `999k` / `1.2M` so the cluster's powerups pill
/// (and the narrow analytics bar reusing the same tracker button) never grows
/// past the allocator's fixed `clusterGutter` — raw 4-5 digit vocab counts
/// overlapped the right column's card (#7508). The displayed string never
/// exceeds 4 characters for any count a learner can reach.
///
/// Deliberately NOT locale-aware (`NumberFormat.compact` renders e.g. Spanish
/// `1,2 mil`, which is wider than the raw digits and defeats the width bound);
/// the fixed `k`/`M` suffix is the games-convention compromise. Exact counts
/// stay available to assistive tech via the tracker's semantics label.
///
/// Values are floored, never rounded up, so a count is never overstated
/// (999,999 is `999k`, not `1M`).
String compactCount(int count) {
  if (count < 1000) return '$count';
  if (count < 1000000) return _abbreviate(count, 1000, 'k');
  return _abbreviate(count, 1000000, 'M');
}

String _abbreviate(int count, int unit, String suffix) {
  final whole = count ~/ unit;
  // Two-plus whole units: no room (or need) for a decimal — "12k", "999k".
  if (whole >= 10) return '$whole$suffix';
  // One decimal place, floored — "1.2k"; drop a zero decimal — "2k".
  final tenth = (count * 10 ~/ unit) % 10;
  return tenth == 0 ? '$whole$suffix' : '$whole.$tenth$suffix';
}

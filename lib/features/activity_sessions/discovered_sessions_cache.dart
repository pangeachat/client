import 'package:collection/collection.dart';

import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';

/// Process-wide cache of the `room_preview` data the world map's session
/// discovery already fetched, keyed by activity id (and, within each, by room
/// id). Lets the activity start page render its "join open session" list
/// **instantly** for a pin the map already knows is joinable — no second server
/// round-trip.
///
/// A miss (an activity opened by deep link without visiting the map first) falls
/// back to the start page's own fetch, so this is purely an optimization, never a
/// correctness requirement. Replaced wholesale on each discovery pass; the
/// staleness window is bounded by the map's discovery cadence, and the join
/// action re-validates against the server anyway. See world-map.instructions.md
/// ("Discovering joinable sessions").
class DiscoveredSessionsCache {
  DiscoveredSessionsCache._();
  static final DiscoveredSessionsCache instance = DiscoveredSessionsCache._();

  final Map<String, Map<String, RoomSummaryResponse>> _byActivityId = {};

  /// Replace the cache with the latest discovery pass (activity id → roomId →
  /// previewed summary).
  void replaceAll(Map<String, Map<String, RoomSummaryResponse>> byActivityId) {
    _byActivityId
      ..clear()
      ..addAll(byActivityId);
  }

  /// The previewed sessions for [activityId] (roomId → summary), or null on a
  /// miss — in which case the caller should fetch.
  Map<String, RoomSummaryResponse>? forActivity(String activityId) =>
      _byActivityId[activityId];

  /// The first still-open previewed session for [activityId] — the accurate
  /// participant/seat source for a joinable pin whose session the learner has
  /// not joined (discovered or invited), where local room state is absent or
  /// stripped (#7488).
  RoomSummaryResponse? bestOpenSummary(String activityId) =>
      _byActivityId[activityId]?.values.firstWhereOrNull(
        (s) => s.isActivityOpenToJoin,
      );

  void clear() => _byActivityId.clear();
}

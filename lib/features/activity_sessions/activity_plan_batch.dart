import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_response.dart';

/// Request body for `POST /choreo/v2/activity/batch`.
///
/// The batch read is the many-at-once form of `GET /v2/activity/{id}`. It saves
/// round trips, not allowance: the backend charges its read budget per activity,
/// so a batch costs what the same reads would have cost one at a time.
class ActivityPlanBatchRequest {
  /// Distinct activity ids, in request order.
  final List<String> activityIds;

  /// The viewer's display language, applied to every activity in the batch —
  /// which is why a batch only ever groups keys that share one.
  final String? l1;

  /// Pinned content-signatures by activity id. Ids absent from it resolve to
  /// latest, exactly as omitting `?version=` does on the single read.
  final Map<String, String> versions;

  const ActivityPlanBatchRequest({
    required this.activityIds,
    this.l1,
    this.versions = const {},
  });

  Map<String, dynamic> toJson() => {
    'activity_ids': activityIds,
    if (l1 != null && l1!.isNotEmpty) 'l1': l1,
    if (versions.isNotEmpty) 'versions': versions,
  };
}

/// Response of `POST /choreo/v2/activity/batch`.
///
/// Three outcomes per activity, deliberately kept apart. `removed` and
/// `unavailable` both render as "no plan", so collapsing them would let a
/// backend outage mark a live catalog as deleted — the same distinction the
/// single read makes between 404 and 503.
class ActivityPlanBatchResponse {
  /// Plans that were read, by activity id. Each is the same body the single
  /// read returns, fallback signals included.
  final Map<String, ActivityPlanFetchResponse> activities;

  /// Confirmed gone. Callers may stop asking for these.
  final List<String> removed;

  /// The read failed; the activity may be perfectly healthy. Retryable, and
  /// never to be treated as removed.
  final List<String> unavailable;

  const ActivityPlanBatchResponse({
    this.activities = const {},
    this.removed = const [],
    this.unavailable = const [],
  });

  factory ActivityPlanBatchResponse.fromJson(Map<String, dynamic> json) {
    final raw =
        (json['activities'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ActivityPlanBatchResponse(
      activities: {
        for (final entry in raw.entries)
          entry.key: ActivityPlanFetchResponse.fromJson(
            (entry.value as Map).cast<String, dynamic>(),
          ),
      },
      removed:
          (json['removed'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      unavailable:
          (json['unavailable'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }
}

/// A batch read came back without a plan for an activity it asked for — the
/// backend reported it `unavailable`, or omitted it.
///
/// Typed so the report says what happened rather than arriving as a bare
/// instance, and so it is distinguishable from a request that failed outright:
/// the HTTP call succeeded, and only some of what it carried did not.
class ActivityBatchUnsatisfied implements Exception {
  const ActivityBatchUnsatisfied();

  @override
  String toString() =>
      'ActivityBatchUnsatisfied: the batch returned no plan for one or more '
      'activities it was asked for';
}

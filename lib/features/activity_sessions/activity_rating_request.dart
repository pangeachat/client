enum ActivityRatingValue {
  up,
  down;

  String get wireName => name;
}

class ActivityRatingRequest {
  final String activityId;
  final ActivityRatingValue rating;

  /// Optional free-text comment; moderated server-side at post time (a flagged
  /// comment rejects the whole submission with 422).
  final String? comment;

  /// The session's pinned content-signature (the version the rater actually
  /// played), recorded for analytics. Not part of dedup — one opinion per
  /// (user, activity), upserted. Null for legacy embedded-plan rooms.
  final String? versionStamp;

  /// Endpoint-test flag: skips only the live moderation call server-side.
  final bool mock;

  const ActivityRatingRequest({
    required this.activityId,
    required this.rating,
    this.comment,
    this.versionStamp,
    this.mock = false,
  });

  Map<String, dynamic> toJson() => {
    'activity_id': activityId,
    'rating': rating.wireName,
    if (comment != null && comment!.isNotEmpty) 'comment': comment,
    if (versionStamp != null) 'version_stamp': versionStamp,
    'mock': mock,
  };
}

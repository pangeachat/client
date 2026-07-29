class ActivityRatingResponse {
  final String activityId;

  /// Up-fraction 0..1 across all raters.
  final double ratingAverage;
  final int ratingCount;

  const ActivityRatingResponse({
    required this.activityId,
    required this.ratingAverage,
    required this.ratingCount,
  });

  factory ActivityRatingResponse.fromJson(Map<String, dynamic> json) =>
      ActivityRatingResponse(
        activityId: json['activity_id'] as String,
        ratingAverage: (json['rating_average'] as num).toDouble(),
        ratingCount: (json['rating_count'] as num).toInt(),
      );
}

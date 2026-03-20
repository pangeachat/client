class CourseMediaInfo {
  final String uuid;
  final String url;
  final String? thumbnailUrl;
  final String? mediumUrl;

  CourseMediaInfo({
    required this.uuid,
    required this.url,
    this.thumbnailUrl,
    this.mediumUrl,
  });

  /// Returns the best URL for the given display width.
  /// Uses thumbnail for <=256px, medium for <=512px, original for larger.
  String urlForWidth(double width) {
    if (width <= 256 && thumbnailUrl != null) return thumbnailUrl!;
    if (width <= 512 && mediumUrl != null) return mediumUrl!;
    return mediumUrl ?? url;
  }
}

class CourseSettingsModel {
  final bool requireAnalyticsAccess;

  const CourseSettingsModel({this.requireAnalyticsAccess = false});

  Map<String, dynamic> toJson() => {
    'require_analytics_access': requireAnalyticsAccess,
  };

  static CourseSettingsModel fromJson(Map<String, dynamic> json) {
    return CourseSettingsModel(
      requireAnalyticsAccess: json['require_analytics_access'] ?? false,
    );
  }

  CourseSettingsModel copyWith({bool? requireAnalyticsAccess}) {
    return CourseSettingsModel(
      requireAnalyticsAccess:
          requireAnalyticsAccess ?? this.requireAnalyticsAccess,
    );
  }
}

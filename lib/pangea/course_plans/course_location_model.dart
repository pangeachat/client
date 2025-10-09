class CourseLocationModel {
  String uuid;
  String name;
  List<String> mediaIds;
  List<double>? coordinates; // [longitude, latitude]

  CourseLocationModel({
    required this.uuid,
    required this.name,
    required this.mediaIds,
    this.coordinates,
  });

  factory CourseLocationModel.fromJson(Map<String, dynamic> json) {
    return CourseLocationModel(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      mediaIds: (json['media_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      coordinates: (json['coordinates'] as List<dynamic>?)
          ?.map((e) => e as double)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'media_ids': mediaIds,
      'coordinates': coordinates,
    };
  }
}

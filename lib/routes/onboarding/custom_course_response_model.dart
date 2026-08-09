class CustomCourseResponseModel {
  final String id;
  final String status;

  const CustomCourseResponseModel({required this.id, required this.status});

  static CustomCourseResponseModel fromJson(Map<String, dynamic> json) {
    return CustomCourseResponseModel(id: json["id"], status: json["status"]);
  }
}

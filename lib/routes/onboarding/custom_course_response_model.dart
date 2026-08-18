import 'package:fluffychat/pangea/common/utils/base_response.dart';

class CustomCourseResponseModel extends BaseResponse {
  final String id;
  final String status;

  const CustomCourseResponseModel({required this.id, required this.status});

  static CustomCourseResponseModel fromJson(Map<String, dynamic> json) {
    return CustomCourseResponseModel(id: json["id"], status: json["status"]);
  }

  @override
  Map<String, dynamic> toJson() => {"id": id, "status": status};
}

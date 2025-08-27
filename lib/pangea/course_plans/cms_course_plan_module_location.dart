import 'package:fluffychat/pangea/payload_client/user_reference.dart';

/// Represents a course plan module location from the CMS API
class CmsCoursePlanModuleLocation {
  final String id;
  final String name;
  final List<double>?
      coordinates; // [longitude, latitude] - minItems: 2, maxItems: 2
  final List<dynamic>
      coursePlanModules; // Can contain strings or CoursePlanModule objects
  final UserReference? createdBy;
  final UserReference? updatedBy;
  final String updatedAt;
  final String createdAt;

  CmsCoursePlanModuleLocation({
    required this.id,
    required this.name,
    this.coordinates,
    required this.coursePlanModules,
    this.createdBy,
    this.updatedBy,
    required this.updatedAt,
    required this.createdAt,
  });

  factory CmsCoursePlanModuleLocation.fromJson(Map<String, dynamic> json) {
    return CmsCoursePlanModuleLocation(
      id: json['id'] as String,
      name: json['name'] as String,
      coordinates: (json['coordinates'] as List<dynamic>?)
          ?.map((coord) => (coord as num).toDouble())
          .toList(),
      coursePlanModules: json['coursePlanModules'] as List<dynamic>,
      createdBy: json['createdBy'] != null
          ? UserReference.fromJson(json['createdBy'] as Map<String, dynamic>)
          : null,
      updatedBy: json['updatedBy'] != null
          ? UserReference.fromJson(json['updatedBy'] as Map<String, dynamic>)
          : null,
      updatedAt: json['updatedAt'] as String,
      createdAt: json['createdAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'coordinates': coordinates,
      'coursePlanModules': coursePlanModules,
      'createdBy': createdBy?.toJson(),
      'updatedBy': updatedBy?.toJson(),
      'updatedAt': updatedAt,
      'createdAt': createdAt,
    };
  }
}

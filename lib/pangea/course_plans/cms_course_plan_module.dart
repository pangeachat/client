import 'package:fluffychat/pangea/course_plans/cms_course_plan_activity.dart';
import 'package:fluffychat/pangea/course_plans/cms_course_plan_module_location.dart';
import 'package:fluffychat/pangea/payload_client/join_field.dart';
import 'package:fluffychat/pangea/payload_client/user_reference.dart';

/// Represents a course plan module from the CMS API
class CmsCoursePlanModule {
  final String id;
  final String title;
  final String description;
  final JoinField<CmsCoursePlanActivity> coursePlanActivities;
  final JoinField<CmsCoursePlanModuleLocation> coursePlanModuleLocations;
  final List<dynamic> coursePlans; // Can contain strings or CoursePlan objects
  final UserReference? createdBy;
  final UserReference? updatedBy;
  final String updatedAt;
  final String createdAt;

  CmsCoursePlanModule({
    required this.id,
    required this.title,
    required this.description,
    required this.coursePlanActivities,
    required this.coursePlanModuleLocations,
    required this.coursePlans,
    this.createdBy,
    this.updatedBy,
    required this.updatedAt,
    required this.createdAt,
  });

  factory CmsCoursePlanModule.fromJson(Map<String, dynamic> json) {
    return CmsCoursePlanModule(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      coursePlanActivities: JoinField<CmsCoursePlanActivity>.fromJson(
        json,
        decodeT: (obj) =>
            CmsCoursePlanActivity.fromJson(obj as Map<String, dynamic>),
      ),
      coursePlanModuleLocations:
          JoinField<CmsCoursePlanModuleLocation>.fromJson(
        json,
        decodeT: (obj) =>
            CmsCoursePlanModuleLocation.fromJson(obj as Map<String, dynamic>),
      ),
      coursePlans: json['coursePlans'] as List<dynamic>,
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
      'title': title,
      'description': description,
      'coursePlanActivities': coursePlanActivities.toJson(
        encodeT: (a) => a.toJson(),
      ),
      'coursePlanModuleLocations': coursePlanModuleLocations.toJson(
        encodeT: (a) => a.toJson(),
      ),
      'coursePlans': coursePlans,
      'createdBy': createdBy?.toJson(),
      'updatedBy': updatedBy?.toJson(),
      'updatedAt': updatedAt,
      'createdAt': createdAt,
    };
  }
}

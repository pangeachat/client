import 'package:fluffychat/pangea/course_plans/cms_course_plan_module.dart';
import 'package:fluffychat/pangea/payload_client/join_field.dart';
import 'package:fluffychat/pangea/payload_client/user_reference.dart';

/// Represents a course plan from the CMS API
class CmsCoursePlan {
  final String id;
  final String title;
  final String description;
  final String cefrLevel;
  final String l1; // Language of instruction
  final String l2; // Target language
  final JoinField<CmsCoursePlanModule> coursePlanModules;
  final UserReference? createdBy;
  final UserReference? updatedBy;
  final String updatedAt;
  final String createdAt;

  CmsCoursePlan({
    required this.id,
    required this.title,
    required this.description,
    required this.cefrLevel,
    required this.l1,
    required this.l2,
    required this.coursePlanModules,
    this.createdBy,
    this.updatedBy,
    required this.updatedAt,
    required this.createdAt,
  });

  factory CmsCoursePlan.fromJson(Map<String, dynamic> json) {
    return CmsCoursePlan(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      cefrLevel: json['cefrLevel'] as String,
      l1: json['l1'] as String,
      l2: json['l2'] as String,
      coursePlanModules: JoinField.fromJson(
        json,
        decodeT: (obj) =>
            CmsCoursePlanModule.fromJson(obj as Map<String, dynamic>),
      ),
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
      'cefrLevel': cefrLevel,
      'l1': l1,
      'l2': l2,
      'coursePlanModules': coursePlanModules,
      'createdBy': createdBy?.toJson(),
      'updatedBy': updatedBy?.toJson(),
      'updatedAt': updatedAt,
      'createdAt': createdAt,
    };
  }
}

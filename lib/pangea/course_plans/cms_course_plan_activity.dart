import 'package:fluffychat/pangea/course_plans/cms_course_plan_activity_media.dart';
import 'package:fluffychat/pangea/learning_settings/enums/language_level_type_enum.dart';
import 'package:fluffychat/pangea/payload_client/user_reference.dart';

/// Represents a course plan activity role
class CmsCoursePlanActivityRole {
  final String id;
  final String name;
  final String? avatarUrl;

  CmsCoursePlanActivityRole({
    required this.id,
    required this.name,
    this.avatarUrl,
  });

  factory CmsCoursePlanActivityRole.fromJson(Map<String, dynamic> json) {
    return CmsCoursePlanActivityRole(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
    };
  }
}

/// Represents vocabulary in a course plan activity
class CmsCoursePlanVocab {
  final String lemma;
  final String pos;
  final String? id;

  CmsCoursePlanVocab({
    required this.lemma,
    required this.pos,
    this.id,
  });

  factory CmsCoursePlanVocab.fromJson(Map<String, dynamic> json) {
    return CmsCoursePlanVocab(
      lemma: json['lemma'] as String,
      pos: json['pos'] as String,
      id: json['id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lemma': lemma,
      'pos': pos,
      'id': id,
    };
  }
}

/// Represents a course plan activity from the CMS API
class CoursePlanActivity {
  final String id;
  final String title;
  final String learningObjective;
  final String instructions;
  final String l1; // Language of instruction
  final String l2; // Target language
  final LanguageLevelTypeEnum cefrLevel;
  final List<CmsCoursePlanActivityRole> roles;
  final List<CmsCoursePlanVocab> vocabs;
  final CmsCoursePlanActivityMedia coursePlanActivityMedia;
  final List<dynamic>
      coursePlanModules; // Can contain strings or CoursePlanModule objects
  final UserReference? createdBy;
  final UserReference? updatedBy;
  final String updatedAt;
  final String createdAt;

  CoursePlanActivity({
    required this.id,
    required this.title,
    required this.learningObjective,
    required this.instructions,
    required this.l1,
    required this.l2,
    required this.cefrLevel,
    required this.roles,
    required this.vocabs,
    required this.coursePlanActivityMedia,
    required this.coursePlanModules,
    this.createdBy,
    this.updatedBy,
    required this.updatedAt,
    required this.createdAt,
  });

  factory CoursePlanActivity.fromJson(Map<String, dynamic> json) {
    return CoursePlanActivity(
      id: json['id'] as String,
      title: json['title'] as String,
      learningObjective: json['learningObjective'] as String,
      instructions: json['instructions'] as String,
      l1: json['l1'] as String,
      l2: json['l2'] as String,
      cefrLevel: LanguageLevelTypeEnumExtension.fromString(
        json['cefrLevel'] as String,
      ),
      roles: (json['roles'] as List<dynamic>)
          .map(
            (role) => CmsCoursePlanActivityRole.fromJson(
                role as Map<String, dynamic>),
          )
          .toList(),
      vocabs: (json['vocabs'] as List<dynamic>)
          .map(
            (vocab) => CmsCoursePlanVocab.fromJson(vocab as Map<String, dynamic>),
          )
          .toList(),
      coursePlanActivityMedia: CmsCoursePlanActivityMedia.fromJson(
        json['coursePlanActivityMedia'] as Map<String, dynamic>,
      ),
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
      'title': title,
      'learningObjective': learningObjective,
      'instructions': instructions,
      'l1': l1,
      'l2': l2,
      'cefrLevel': cefrLevel.string,
      'roles': roles.map((role) => role.toJson()).toList(),
      'vocabs': vocabs.map((vocab) => vocab.toJson()).toList(),
      'coursePlanActivityMedia': coursePlanActivityMedia.toJson(),
      'coursePlanModules': coursePlanModules,
      'createdBy': createdBy?.toJson(),
      'updatedBy': updatedBy?.toJson(),
      'updatedAt': updatedAt,
      'createdAt': createdAt,
    };
  }
}

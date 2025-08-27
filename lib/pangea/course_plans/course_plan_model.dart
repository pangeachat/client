import 'package:fluffychat/pangea/activity_generator/media_enum.dart';
import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_planner/activity_plan_request.dart';
import 'package:fluffychat/pangea/course_plans/cms_course_plan.dart';
import 'package:fluffychat/pangea/course_plans/cms_course_plan_activity.dart';
import 'package:fluffychat/pangea/course_plans/cms_course_plan_module.dart';
import 'package:fluffychat/pangea/course_plans/cms_course_plan_module_location.dart';
import 'package:fluffychat/pangea/learning_settings/enums/language_level_type_enum.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/utils/p_language_store.dart';
import 'package:fluffychat/pangea/payload_client/extract_from_string_or_t.dart';
import 'package:fluffychat/pangea/payload_client/payload_client.dart';

/// Represents a topic in the course planner response.
class Topic {
  final String title;
  final String description;
  final String location;
  final String uuid;
  final String? imageUrl;

  final List<ActivityPlanModel> activities;

  Topic({
    required this.title,
    required this.description,
    this.location = "Unknown",
    required this.uuid,
    List<ActivityPlanModel>? activities,
    this.imageUrl,
  }) : activities = activities ?? [];

  /// Deserialize from JSON
  factory Topic.fromJson(Map<String, dynamic> json) {
    return Topic(
      title: json['title'] as String,
      description: json['description'] as String,
      location: json['location'] as String? ?? "Unknown",
      uuid: json['uuid'] as String,
      activities: (json['activities'] as List<dynamic>?)
              ?.map(
                (e) => ActivityPlanModel.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      imageUrl: json['image_url'] as String?,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'location': location,
      'uuid': uuid,
      'activities': activities.map((e) => e.toJson()).toList(),
      'image_url': imageUrl,
    };
  }

  List<String> get activityIds => activities.map((e) => e.bookmarkId).toList();
}

/// Represents a course plan in the course planner response.
class CoursePlanModel {
  final String targetLanguage;
  final String languageOfInstructions;
  final LanguageLevelTypeEnum cefrLevel;

  final String title;
  final String description;

  final String uuid;

  final List<Topic> topics;
  final String? imageUrl;

  CoursePlanModel({
    required this.targetLanguage,
    required this.languageOfInstructions,
    required this.cefrLevel,
    required this.title,
    required this.description,
    required this.uuid,
    List<Topic>? topics,
    this.imageUrl,
  }) : topics = topics ?? [];

  int get activities =>
      topics.map((t) => t.activities.length).reduce((a, b) => a + b);

  LanguageModel? get targetLanguageModel =>
      PLanguageStore.byLangCode(targetLanguage);

  LanguageModel? get baseLanguageModel =>
      PLanguageStore.byLangCode(languageOfInstructions);

  String get targetLanguageDisplay =>
      targetLanguageModel?.langCode.toUpperCase() ??
      targetLanguage.toUpperCase();

  String get baseLanguageDisplay =>
      baseLanguageModel?.langCode.toUpperCase() ??
      languageOfInstructions.toUpperCase();

  String? topicID(String activityID) {
    for (final topic in topics) {
      for (final activity in topic.activities) {
        if (activity.bookmarkId == activityID) {
          return topic.uuid;
        }
      }
    }
    return null;
  }

  /// Deserialize from JSON
  factory CoursePlanModel.fromJson(Map<String, dynamic> json) {
    return CoursePlanModel(
      targetLanguage: json['target_language'] as String,
      languageOfInstructions: json['language_of_instructions'] as String,
      cefrLevel: LanguageLevelTypeEnumExtension.fromString(json['cefr_level']),
      title: json['title'] as String,
      description: json['description'] as String,
      uuid: json['uuid'] as String,
      topics: (json['topics'] as List<dynamic>?)
              ?.map((e) => Topic.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      imageUrl: json['image_url'] as String?,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'target_language': targetLanguage,
      'language_of_instructions': languageOfInstructions,
      'cefr_level': cefrLevel.string,
      'title': title,
      'description': description,
      'uuid': uuid,
      'topics': topics.map((e) => e.toJson()).toList(),
      'image_url': imageUrl,
    };
  }

  /// Deserialize from CmsCoursePlan
  static Future<CoursePlanModel> fromCmsCoursePlan(
    CmsCoursePlan cmsCoursePlan,
    PayloadClient payload,
  ) async {
    // Convert modules to topics
    final topics = <Topic>[];
    if (cmsCoursePlan.coursePlanModules.docs != null) {
      final moduleExtractionFutures =
          cmsCoursePlan.coursePlanModules.docs!.map((doc) {
        return extractFromStringOrT(
          doc,
          "course-plan-modules",
          payload,
          CmsCoursePlanModule.fromJson,
        );
      });
      final modules = await Future.wait(moduleExtractionFutures);

      final topicCreationFutures =
          modules.where((module) => module != null).map((module) async {
        // Create futures for location and activities extraction in parallel
        final locationFuture = _extractModuleLocation(module!, payload);
        final activitiesFuture = _extractModuleActivities(module, payload);

        // Wait for both location and activities to complete
        final results = await Future.wait([locationFuture, activitiesFuture]);
        final location = results[0] as String;
        final activities = results[1] as List<ActivityPlanModel>;

        return Topic(
          title: module.title,
          description: module.description,
          location: location,
          uuid: module.id,
          activities: activities,
          // Note: Topic imageUrl would need to be extracted from module if available
        );
      });

      final extractedTopics = await Future.wait(topicCreationFutures);
      topics.addAll(extractedTopics);
    }

    return CoursePlanModel(
      targetLanguage: cmsCoursePlan.l2,
      languageOfInstructions: cmsCoursePlan.l1,
      cefrLevel:
          LanguageLevelTypeEnumExtension.fromString(cmsCoursePlan.cefrLevel),
      title: cmsCoursePlan.title,
      description: cmsCoursePlan.description,
      uuid: cmsCoursePlan.id,
      topics: topics,
      // TODO: @WilsonLe CoursePlan imageUrl would need to be extracted from cmsCoursePlan if available
    );
  }

  /// Extract location name from module
  static Future<String> _extractModuleLocation(
    dynamic module,
    PayloadClient payload,
  ) async {
    String location = "Any";
    if (module.coursePlanModuleLocations.docs?.isNotEmpty == true) {
      final locationWrapper = module.coursePlanModuleLocations.docs!.first;
      final locationObj = await extractFromStringOrT(
        locationWrapper,
        "course-plan-module-locations",
        payload,
        CmsCoursePlanModuleLocation.fromJson,
      );
      if (locationObj != null) {
        location = locationObj.name;
      }
    }
    return location;
  }

  /// Extract activities from module
  static Future<List<ActivityPlanModel>> _extractModuleActivities(
    dynamic module,
    PayloadClient payload,
  ) async {
    final activities = <ActivityPlanModel>[];
    if (module.coursePlanActivities.docs != null) {
      final activityExtractionFutures =
          module.coursePlanActivities.docs!.map((activityWrapper) {
        return extractFromStringOrT(
          activityWrapper,
          "course-plan-activities",
          payload,
          CmsCoursePlanActivity.fromJson,
        );
      });

      final extractedActivities = await Future.wait(activityExtractionFutures);

      for (final activity in extractedActivities) {
        if (activity != null) {
          // Create ActivityPlanRequest
          final req = ActivityPlanRequest(
            topic: module.title,
            mode: "conversation", // Default mode
            objective: activity.learningObjective,
            media: MediaEnum.nan, // Default media
            cefrLevel: activity.cefrLevel,
            languageOfInstructions: activity.l1,
            targetLanguage: activity.l2,
            numberOfParticipants: activity.roles.length.clamp(1, 10),
          );

          // Convert vocab
          final vocab = activity.vocabs
              .map(
                (v) => Vocab(
                  lemma: v.lemma,
                  pos: v.pos,
                ),
              )
              .toList();

          // Convert roles
          final roles = <String, ActivityRole>{};
          for (int i = 0; i < activity.roles.length; i++) {
            final role = activity.roles[i];
            roles['role_$i'] = ActivityRole(
              id: role.id,
              name: role.name,
              avatarUrl: role.avatarUrl,
            );
          }

          final activityModel = ActivityPlanModel(
            req: req,
            title: activity.title,
            learningObjective: activity.learningObjective,
            instructions: activity.instructions,
            vocab: vocab,
            bookmarkId: activity.id,
            roles: roles,
            imageURL: activity.coursePlanActivityMedia.url,
          );

          activities.add(activityModel);
        }
      }
    }
    return activities;
  }
}

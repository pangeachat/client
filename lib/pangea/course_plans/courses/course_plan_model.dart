import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/course_plans/course_info_batch_request.dart';
import 'package:fluffychat/pangea/course_plans/course_media/course_media_repo.dart';
import 'package:fluffychat/pangea/course_plans/course_media/course_media_response.dart';
import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_repo.dart';
import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_response.dart';
import 'package:fluffychat/pangea/learning_settings/enums/language_level_type_enum.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/utils/p_language_store.dart';

/// Represents a course plan in the course planner response.
class CoursePlanModel {
  final String uuid;

  final String targetLanguage;
  final String languageOfInstructions;
  final LanguageLevelTypeEnum cefrLevel;

  final String title;
  final String description;

  final List<String> topicIds;
  final List<String> mediaIds;

  CoursePlanModel({
    required this.targetLanguage,
    required this.languageOfInstructions,
    required this.cefrLevel,
    required this.title,
    required this.description,
    required this.uuid,
    required this.topicIds,
    required this.mediaIds,
  });

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
    for (final topic in loadedTopics.topics) {
      if (topic.activityIds.any((id) => id == activityID)) {
        return topic.uuid;
      }
    }
    return null;
  }

  int get totalActivities => loadedTopics.topics
      .fold(0, (sum, topic) => sum + topic.activityIds.length);

  ActivityPlanModel? activityById(String activityID) {
    for (final topic in loadedTopics.topics) {
      final activity = topic.activityById(activityID);
      if (activity != null) {
        return activity;
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
      uuid: json['uuid'] as String? ?? json['id'] as String,
      topicIds: (json['topic_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      mediaIds: (json['media_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
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
      'topic_ids': topicIds,
      'media_ids': mediaIds,
    };
  }

  bool get topicListComplete => topicIds.length == loadedTopics.topics.length;
  CourseTopicResponse get loadedTopics => CourseTopicRepo.getCached(
        CourseInfoBatchRequest(
          batchId: uuid,
          uuids: topicIds,
        ),
      );
  Future<CourseTopicResponse> fetchTopics() => CourseTopicRepo.get(
        CourseInfoBatchRequest(
          batchId: uuid,
          uuids: topicIds,
        ),
      );

  bool get mediaListComplete =>
      mediaIds.length == loadedMediaUrls.mediaUrls.length;
  CourseMediaResponse get loadedMediaUrls => CourseMediaRepo.getCached(
        CourseInfoBatchRequest(
          batchId: uuid,
          uuids: mediaIds,
        ),
      );
  Future<CourseMediaResponse> fetchMediaUrls() => CourseMediaRepo.get(
        CourseInfoBatchRequest(
          batchId: uuid,
          uuids: mediaIds,
        ),
      );
  String? get imageUrl => loadedMediaUrls.mediaUrls.isEmpty
      ? loadedTopics.topics
          .lastWhereOrNull((topic) => topic.imageUrl != null)
          ?.imageUrl
      : "${Environment.cmsApi}${loadedMediaUrls.mediaUrls.first}";

  Future<void> init() async {
    final courseFutures = <Future>[
      fetchMediaUrls(),
      fetchTopics(),
    ];
    await Future.wait(courseFutures);

    final topicFutures = <Future>[];
    for (final topic in loadedTopics.topics) {
      topicFutures.add(topic.fetchActivities());
      topicFutures.add(topic.fetchLocationMedia());
    }
    await Future.wait(topicFutures);
  }
}

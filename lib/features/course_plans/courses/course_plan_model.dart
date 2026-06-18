import 'package:collection/collection.dart';

import 'package:fluffychat/features/course_plans/course_info_batch_request.dart';
import 'package:fluffychat/features/course_plans/course_media/course_media_repo.dart';
import 'package:fluffychat/features/course_plans/course_media/course_media_response.dart';
import 'package:fluffychat/features/course_plans/course_topics/course_topic_model.dart';
import 'package:fluffychat/features/course_plans/course_topics/course_topic_repo.dart';
import 'package:fluffychat/features/course_plans/course_topics/course_topic_translation_request.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/pangea/common/network/media_url.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A course-shape model the picker (`NewCoursePage`) and the
/// `SelectedCourseView` detail render from. Originally written against the v1
/// ``course-plans`` collection.
///
/// **v3 catalog status.** The v3 read paths (`QuestRepo.outline`,
/// `QuestRepo.questPins`, `QuestRepo.activity`) have replaced this model's
/// v1-only fan-out (`topicIds` → topics → locations → activities → media). The
/// picker now also receives v3 rows via [QuestPlansRepo.searchByFilter] as
/// **synthesized** `CoursePlanModel`s that carry id + display fields only —
/// `topicIds` is a placeholder list (`'quest:<id>:mission:<i>'`) sized to the
/// quest's mission count so the "N modules" chip reads correctly, and
/// `mediaIds` is empty.
///
/// The v1 methods on this class — [topicListComplete], [loadedTopics],
/// [activityIDs], [fetchTopics], [mediaListComplete], [loadedMediaUrls],
/// [fetchMediaUrls], [imageUrl] — query the v1 cms collections directly and
/// **do not work on quest-synthesized instances** (the placeholder topic ids
/// never resolve). New consumers should either:
///
/// - go through the v3 path (`QuestRepo.outline(uuid)` for the full
///   per-mission activity grouping; `QuestRepo.questPins(uuid)` for the world
///   map pin list); or
/// - read only the carrying fields below (`uuid`, `title`, `description`,
///   `targetLanguage`, `languageOfInstructions`, `cefrLevel`) which both v1
///   and synthesized-v3 instances populate consistently.
///
/// `CoursePlanProvider.loadTopics` already short-circuits when it detects a
/// quest-synthesized model (placeholder `topicIds` starting with `quest:`),
/// so v1 consumers running through that mixin keep working without checking.
class CoursePlanModel {
  final String uuid;

  final String targetLanguage;
  final String languageOfInstructions;
  final LanguageLevelTypeEnum cefrLevel;

  final String title;
  final String description;

  final List<String> topicIds;
  final List<String> mediaIds;

  final DateTime updatedAt;
  final DateTime createdAt;

  CoursePlanModel({
    required this.targetLanguage,
    required this.languageOfInstructions,
    required this.cefrLevel,
    required this.title,
    required this.description,
    required this.uuid,
    required this.topicIds,
    required this.mediaIds,
    required this.updatedAt,
    required this.createdAt,
  });

  LanguageModel? get targetLanguageModel =>
      PLanguageStore.byLangCode(targetLanguage);

  LanguageModel? get baseLanguageModel =>
      PLanguageStore.byLangCode(languageOfInstructions);

  String get targetLanguageDisplay =>
      targetLanguageModel?.langCode.toUpperCase() ??
      targetLanguage.toUpperCase();

  /// Deserialize from JSON
  factory CoursePlanModel.fromJson(Map<String, dynamic> json) {
    return CoursePlanModel(
      targetLanguage: json[ModelKey.targetLanguage] as String,
      languageOfInstructions: json['language_of_instructions'] as String,
      cefrLevel: LanguageLevelTypeEnum.fromString(json['cefr_level']),
      title: json['title'] as String,
      description: json['description'] as String,
      uuid: json['uuid'] as String,
      topicIds:
          (json['topic_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      mediaIds:
          (json['media_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      updatedAt: DateTime.parse(json['updated_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      ModelKey.targetLanguage: targetLanguage,
      'language_of_instructions': languageOfInstructions,
      'cefr_level': cefrLevel.string,
      'title': title,
      'description': description,
      'uuid': uuid,
      'topic_ids': topicIds,
      'media_ids': mediaIds,
      'updated_at': updatedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  @Deprecated('v1-only. Use QuestRepo.outline(uuid) for the v3 per-mission grouping.')
  bool get topicListComplete => topicIds.length == loadedTopics.length;

  @Deprecated('v1-only. Use QuestRepo.outline(uuid) for the v3 per-mission grouping.')
  Map<String, CourseTopicModel> get loadedTopics => CourseTopicRepo.getCached(
    TranslateTopicRequest(
      topicIds: topicIds,
      l1: MatrixState.pangeaController.userController.userL1Code!,
    ),
  ).topics;

  @Deprecated('v1-only. Use QuestRepo.outline(uuid) and read its groups instead.')
  Set<String> get activityIDs =>
      loadedTopics.values.expand((topic) => topic.activityIds).toSet();

  @Deprecated('v1-only. Quest-synthesized models do not need this; QuestRepo.outline fetches missions + activities.')
  Future<Map<String, CourseTopicModel>> fetchTopics() async {
    final resp = await CourseTopicRepo.get(
      TranslateTopicRequest(
        topicIds: topicIds,
        l1: MatrixState.pangeaController.userController.userL1Code!,
      ),
      uuid,
    );
    return resp.topics;
  }

  @Deprecated('v1-only. v3 quests carry no course-level media; activity media lives on `plan.media[]` and is resolved via ActivityMediaRepo.')
  bool get mediaListComplete =>
      mediaIds.length == loadedMediaUrls.mediaUrls.length;

  @Deprecated('v1-only. v3 quests carry no course-level media; activity media lives on `plan.media[]` and is resolved via ActivityMediaRepo.')
  CourseMediaResponse get loadedMediaUrls => CourseMediaRepo.getCached(
    CourseInfoBatchRequest(batchId: uuid, uuids: mediaIds),
  );

  @Deprecated('v1-only. v3 quests carry no course-level media; activity media lives on `plan.media[]` and is resolved via ActivityMediaRepo.')
  Future<CourseMediaResponse> fetchMediaUrls() => CourseMediaRepo.get(
    CourseInfoBatchRequest(batchId: uuid, uuids: mediaIds),
  );

  /// Picker thumbnail. Returns null for v3 quest-synthesized models (no
  /// course-level media). Card UI falls back to an avatar with initials.
  Uri? get imageUrl {
    if (loadedMediaUrls.mediaUrls.isEmpty) {
      return loadedTopics.values
          .lastWhereOrNull((topic) => topic.imageUrl != null)
          ?.imageUrl;
    }
    final media = loadedMediaUrls.mediaUrls.first;
    return resolveMediaUrl(media.mediumUrl ?? media.url);
  }
}

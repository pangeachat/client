import 'package:fluffychat/features/course_plans/courses/course_filter.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/course_plans/payload_client/payload_client.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Picker-side adapter for the v3 ``quest-plans`` cms collection.
///
/// The picker UI ([NewCoursePage]) is built around [CoursePlanModel], so this
/// repo *synthesizes* a [CoursePlanModel] from each quest-plans row rather than
/// minting a parallel model class — every card, chip, dialog, and the
/// downstream room-creation flow ([SelectedCourse.launchCourse]) keeps working
/// unchanged. The v3 outline that lights up after room creation
/// ([QuestRepo.outline]) reads the *real* quest by id, so the synthesized
/// model only needs to carry id + display fields, not the heavyweight v1
/// `topicIds`/`mediaIds` plumbing.
///
/// Field map (quest-plans row → synthesized [CoursePlanModel]):
/// - ``id`` → ``uuid`` (this id is what gets written into the new room's
///   ``pangea.course_plan`` state event, and [QuestRepo.outline] uses it
///   verbatim — the id-space is shared).
/// - ``res.name`` → ``title``.
/// - ``res.description`` → ``description``.
/// - ``req.target_language`` → ``targetLanguage`` (L2).
/// - ``req.target_l1`` → ``languageOfInstructions`` (L1).
/// - ``req.target_cefr`` → ``cefrLevel``.
/// - ``res.learning_objective_sequence.length`` → ``topicIds.length`` as a
///   non-empty placeholder list, so the "N modules" chip reads correctly. The
///   placeholder strings are never resolved against the v1 topics collection
///   because no v3 surface calls [CoursePlanModel.fetchTopics] on a
///   quest-synthesized row.
class QuestPlansRepo {
  static const String _collection = 'quest-plans';

  static PayloadClient _client() => PayloadClient(
    baseUrl: Environment.cmsApi,
    accessToken: MatrixState.pangeaController.userController.accessToken,
  );

  /// Translate a v1-style [CourseFilter] into a v3 quest-plans `where` clause.
  /// Field names differ (v1: top-level ``l1``/``l2``/``cefrLevel``; v3: nested
  /// under ``req.target_l1``/``req.target_language``/``req.target_cefr``).
  static Map<String, dynamic> _whereFor(CourseFilter filter) {
    final clauses = <Map<String, dynamic>>[];
    if (filter.targetLanguage != null) {
      clauses.add({
        'req.target_language': {'equals': filter.targetLanguage!.langCodeShort},
      });
    }
    if (filter.languageOfInstructions != null) {
      clauses.add({
        'req.target_l1': {
          'equals': filter.languageOfInstructions!.langCodeShort,
        },
      });
    }
    if (filter.cefrLevel != null) {
      clauses.add({
        'req.target_cefr': {'equals': filter.cefrLevel!.string},
      });
    }
    if (clauses.isEmpty) return const {};
    if (clauses.length == 1) return clauses.first;
    return {'and': clauses};
  }

  /// Paginated picker search over quest-plans, in the same shape as
  /// [CoursePlansRepo.searchByFilter] so the picker can merge both sources.
  static Future<({List<CoursePlanModel> quests, bool hasNextPage})>
  searchByFilter({
    required CourseFilter filter,
    int page = 1,
    int limit = 10,
  }) async {
    final resp = await _client().find<CoursePlanModel?>(
      _collection,
      _fromQuestPlanJson,
      page: page,
      limit: limit,
      where: _whereFor(filter),
      depth: 0,
    );
    final quests = resp.docs.whereType<CoursePlanModel>().toList();
    return (quests: quests, hasNextPage: resp.hasNextPage);
  }

  /// Load one quest-plans row as a synthesized [CoursePlanModel]. Used by
  /// [CoursePlanProvider.loadCourse] as the fallback path when a course id
  /// doesn't resolve in v1 ``course-plans`` (the id-space is shared, so an
  /// id that 404s in v1 may still resolve in v3).
  static Future<CoursePlanModel?> get(String questId) async {
    try {
      return await _client().findById<CoursePlanModel?>(
        _collection,
        questId,
        _fromQuestPlanJson,
      );
    } catch (_) {
      return null;
    }
  }

  /// JSON → synthesized [CoursePlanModel]. Returns ``null`` on a missing /
  /// malformed quest-plans row so the caller can filter it out cleanly
  /// instead of inserting a broken card.
  static CoursePlanModel? _fromQuestPlanJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final req = json['req'] as Map<String, dynamic>?;
    final res = json['res'] as Map<String, dynamic>?;
    if (id == null || req == null || res == null) return null;

    final name = res['name'] as String?;
    final description = res['description'] as String?;
    final targetLanguage = req['target_language'] as String?;
    final targetL1 = req['target_l1'] as String?;
    final targetCefr = req['target_cefr'] as String?;
    if (name == null ||
        description == null ||
        targetLanguage == null ||
        targetL1 == null ||
        targetCefr == null) {
      return null;
    }

    final sequence = res['learning_objective_sequence'] as List<dynamic>?;
    final missionCount = sequence?.length ?? 0;
    // Placeholder strings carry the *count* so the "N modules" chip reads
    // correctly. They are never resolved against the v1 ``course-plan-topics``
    // collection — no v3 surface walks ``topicIds`` on a synthesized model.
    final placeholderTopicIds = List<String>.generate(
      missionCount,
      (i) => 'quest:$id:mission:$i',
    );

    return CoursePlanModel(
      uuid: id,
      title: name,
      description: description,
      targetLanguage: targetLanguage,
      languageOfInstructions: targetL1,
      cefrLevel: LanguageLevelTypeEnum.fromString(targetCefr),
      topicIds: placeholderTopicIds,
      mediaIds: const [],
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

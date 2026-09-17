import 'package:fluffychat/features/activity_sessions/activity_media_repo.dart';
import 'package:fluffychat/features/course_plans/courses/course_filter.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/course_plans/payload_client/payload_client.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
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
/// - ``owner_mxid`` → ``ownerId`` (the credit; the plain-text mirror, never
///   the ``owner`` relationship — a learner's token cannot read
///   ``matrix-users``).
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
  ///
  /// The ``hidden`` clause is unconditional: a retired quest must not be
  /// reachable from the picker by paging or by any filter combination. It is
  /// scoped to *search* on purpose — [get] and [getMany] stay unfiltered so a
  /// learner whose course was built from a since-hidden quest keeps resolving
  /// it. Hiding a quest never touches the activities under its objectives;
  /// those carry their own ``hidden`` flag.
  static Map<String, dynamic> _whereFor(CourseFilter filter) {
    final clauses = <Map<String, dynamic>>[
      {
        'hidden': {'not_equals': true},
      },
    ];
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
    final resp = await _client().find<Map<String, dynamic>>(
      _collection,
      (json) => json,
      page: page,
      limit: limit,
      where: _whereFor(filter),
      depth: 0,
    );
    final imageUrls = await _resolveImageUrls(resp.docs);
    final quests = resp.docs
        .map((json) => _fromQuestPlanJson(json, imageUrls: imageUrls))
        .whereType<CoursePlanModel>()
        .toList();
    return (quests: quests, hasNextPage: resp.hasNextPage);
  }

  /// Load one quest-plans row as a synthesized [CoursePlanModel]. Used by
  /// [CoursePlanProvider.loadCourse] as the fallback path when a course id
  /// doesn't resolve in v1 ``course-plans`` (the id-space is shared, so an
  /// id that 404s in v1 may still resolve in v3).
  ///
  /// Shares [QuestRepo.removedQuests] — both read the same ``quest-plans``
  /// collection by id, so a 404 either sees is the same fact. A remembered
  /// verdict answers null without a request, the same value this method's own
  /// 404 handling returns (#8691); callers' handling of a missing quest —
  /// e.g. onboarding continuing without course details (#8593) — is unchanged.
  static Future<CoursePlanModel?> get(String questId) async {
    if (await QuestRepo.removedQuests.contains(questId)) return null;
    try {
      final json = await _client().findById<Map<String, dynamic>>(
        _collection,
        questId,
        (json) => json,
      );
      final imageUrls = await _resolveImageUrls([json]);
      final plan = _fromQuestPlanJson(json, imageUrls: imageUrls);
      QuestRepo.removedQuests.unmark(questId);
      return plan;
    } catch (e) {
      if (PangeaHttpException.statusCodeOf(e) == 404) {
        QuestRepo.removedQuests.mark(questId);
      }
      return null;
    }
  }

  /// Resolve a page of quest ids in one request, keyed by id.
  ///
  /// The catalog hands back a page of course ids at a time; fetching them one
  /// by one costs a round trip per card, which is felt directly as browse
  /// latency. Ids that do not resolve are simply absent from the result.
  ///
  /// [requireMissions] defaults to true, so a Mission-less quest is absent too.
  /// A caller that genuinely wants every row a page of ids resolves to —
  /// counting or repairing them, rather than offering them to a learner — opts
  /// out explicitly.
  static Future<Map<String, CoursePlanModel>> getMany(
    List<String> questIds, {
    bool requireMissions = true,
  }) async {
    if (questIds.isEmpty) return const {};
    final resp = await _client().find<Map<String, dynamic>>(
      _collection,
      (json) => json,
      limit: questIds.length,
      where: {
        'id': {'in': questIds},
      },
      depth: 0,
    );
    final imageUrls = await _resolveImageUrls(resp.docs);
    final result = <String, CoursePlanModel>{};
    for (final json in resp.docs) {
      final plan = _fromQuestPlanJson(
        json,
        requireMissions: requireMissions,
        imageUrls: imageUrls,
      );
      if (plan != null) result[plan.uuid] = plan;
    }
    return result;
  }

  /// Batch-resolves each rows `image.upload_id` via [ActivityMediaRepo.resolve]
  /// A row with no image, or a lookup miss,
  /// is simply absent from the result; callers treat `imageUrls[id] == null`
  /// the same as no image (letter avatar fallback), not as an error.
  static Future<Map<String, Uri>> _resolveImageUrls(
    List<Map<String, dynamic>> rawDocs,
  ) async {
    final uploadIds = rawDocs
        .map((json) => json['image'] as Map?)
        .map((image) => image?['upload_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    if (uploadIds.isEmpty) return const {};

    try {
      final resolved = await ActivityMediaRepo.resolve(uploadIds);
      final urls = <String, Uri>{};
      for (final entry in resolved.entries) {
        // Already an absolute URL — ActivityMediaRepo.resolve() normalizes
        // a relative CMS path itself, for every caller, not just this one.
        final raw = entry.value.thumbnailUrl ?? entry.value.url;
        final uri = Uri.tryParse(raw);
        if (uri != null) urls[entry.key] = uri;
      }
      return urls;
    } catch (_) {
      // A media lookup failure must not sink the whole quest list — it
      // degrades to the same letter-avatar fallback as a quest with no image.
      return const {};
    }
  }

  /// JSON → synthesized [CoursePlanModel]. Returns ``null`` on a missing /
  /// malformed quest-plans row so the caller can filter it out cleanly
  /// instead of inserting a broken card.
  static CoursePlanModel? _fromQuestPlanJson(
    Map<String, dynamic> json, {
    bool requireMissions = true,
    Map<String, Uri>? imageUrls,
  }) {
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
    // A quest-plan with no missions has no content to build a course from, and
    // none to join one for either: it renders as a "0 activities" card that
    // leads nowhere. Every surface that offers a course to a learner drops it —
    // the creation picker (#7700) and the browse-public catalog (#9088) alike;
    // see course-preview.instructions.md.
    //
    // Hence the default. This method is usually passed as a tear-off, which
    // silently takes it, and a call site that quietly inherited the opposite
    // value is exactly how browse came to list cards the preview refused
    // (#9088). Opt out deliberately, at the call site, or not at all.
    if (requireMissions && missionCount == 0) return null;
    // Placeholder strings carry the *count* so the "N modules" chip reads
    // correctly. They are never resolved against the v1 ``course-plan-topics``
    // collection — no v3 surface walks ``topicIds`` on a synthesized model.
    final placeholderTopicIds = List<String>.generate(
      missionCount,
      (i) => 'quest:$id:mission:$i',
    );

    // Top-level field, a sibling of req/res, not nested inside either.
    final imageUploadId = (json['image'] as Map?)?['upload_id'] as String?;

    return CoursePlanModel(
      uuid: id,
      title: name,
      description: description,
      targetLanguage: targetLanguage,
      languageOfInstructions: targetL1,
      cefrLevel: LanguageLevelTypeEnum.fromString(targetCefr),
      topicIds: placeholderTopicIds,
      mediaIds: const [],
      // Populated by generate-quest's media-first cover search, or hand-set
      // in the CMS admin for a quest made another way — absent on a quest
      // whose search found nothing (or hasn't run), which is a normal state,
      // not an error. See quest-plans.ts.
      imageUrl: imageUrls?[imageUploadId],
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      // Who is credited on the create-course page. The plain-text mirror, not
      // the `owner` relationship beside it: `owner` is a per-env matrix-users
      // row id, and that collection is service- and admin-read only, so a
      // learner's token can read this quest and never resolve the person
      // behind it. Absent on a row whose owner was never recorded — which is
      // NOT the same as Pangea's own (`CoursePlanModel.ownerId`).
      ownerId: json['owner_mxid'] as String?,
    );
  }
}

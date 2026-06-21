import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/features/activity_sessions/activity_media_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/course_plans/payload_client/payload_client.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/activity_v2_mapper.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// An activity in a quest outline: its id plus the full plan, so the card
/// renders and a session can open without a refetch.
class QuestActivity {
  final String activityId;
  final ActivityPlanModel plan;
  const QuestActivity({required this.activityId, required this.plan});
}

/// A Learning Objective (Mission) with the activities that satisfy it, in
/// quest order. A learner advances by completing any activity in the bucket.
class QuestObjectiveGroup {
  final LearningObjective objective;
  final List<QuestActivity> activities;
  const QuestObjectiveGroup({
    required this.objective,
    required this.activities,
  });
}

/// A fully-resolved quest for the outline UI: the quest plus its objective
/// groups, in order.
class QuestOutline {
  final QuestPlan quest;
  final List<QuestObjectiveGroup> groups;
  const QuestOutline({required this.quest, required this.groups});
}

/// v3 read layer for quests / learning-objectives / activities-v2.
///
/// Reads CMS directly (Matrix Bearer auth), canonical only — localization is
/// choreo's concern, consumed later when these reads swap to choreo endpoints
/// (this repo is the swap point; callers don't change).
///
/// Deliberately NOT modeled on the v1 course-plan fan-out (plan → localized
/// courses → topics → locations → activities, five sequential round-trips):
///  - an outline is **three flat reads** — the quest, then the LO-text batch
///    and the `activities-v2` query (all the quest's LOs at once) in parallel;
///  - map pins are **one** thin read off the activities' own coordinates (no
///    topic/location join, no ring-offset hack).
class QuestRepo {
  static const String _questPlans = 'quest-plans';
  static const String _learningObjectives = 'learning-objectives';
  static const String _activities = 'activities-v2';

  /// Thin projection for map pins — card fields only, no plan body.
  static const Map<String, dynamic> _pinSelect = {
    'res': {
      'plan': {
        'activity_id': true,
        'title': true,
        'l2': true,
        'coordinates': true,
      },
    },
    'learningObjectiveRefs': true,
  };

  static PayloadClient _client() => PayloadClient(
    baseUrl: Environment.cmsApi,
    accessToken: MatrixState.pangeaController.userController.accessToken,
  );

  /// Resolve every plan's media `upload_id`s to CDN URLs in ONE batched read,
  /// returning the plans with resolved media. `upload_id` is plain text on
  /// `activities-v2` (not a relationship), so a depth read never hydrates the
  /// URL — this second `media`-collection read is the contract. See
  /// `.github/.github/instructions/activities.instructions.md`.
  static Future<List<ActivityPlanModel>> _withResolvedMedia(
    List<ActivityPlanModel> plans,
  ) async {
    final ids = plans
        .expand((p) => p.media)
        .map((b) => b.uploadId)
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return plans;
    final resolved = await ActivityMediaRepo.resolve(ids);
    return plans
        .map((p) => p.withMedia(_applyResolved(p.media, resolved)))
        .toList();
  }

  static List<ActivityMediaBlock> _applyResolved(
    List<ActivityMediaBlock> media,
    Map<String, ResolvedMedia> resolved,
  ) => media.map((block) {
    final r = block.uploadId == null ? null : resolved[block.uploadId];
    return r == null
        ? block
        : block.copyWithResolved(
            resolvedUrl: r.url,
            resolvedThumbnailUrl: r.thumbnailUrl,
            resolvedMediumUrl: r.mediumUrl,
          );
  }).toList();

  /// `where` matching any activity that satisfies one of [loIds] at [l2].
  static Map<String, dynamic> _loAtL2Where(List<String> loIds, String l2) => {
    'and': [
      {
        'or': [
          for (final id in loIds)
            {
              'learningObjectiveRefs': {'contains': id},
            },
        ],
      },
      {
        'res.plan.l2': {'equals': l2},
      },
    ],
  };

  /// The quest with its ordered Learning Objective ids (one read). LO text is
  /// NOT populated by depth (Payload leaves the relationship-in-array a bare
  /// id), so [learningObjectives] resolves it in a separate batch read.
  static Future<QuestPlan> quest(String questId) => _client().findById(
    _questPlans,
    questId,
    (json) => QuestPlan.fromJson(json),
  );

  /// The full Learning Objectives for [ids], resolved in one batched read.
  static Future<Map<String, LearningObjective>> learningObjectives(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final resp = await _client().find(
      _learningObjectives,
      (json) => LearningObjective.fromJson(json),
      where: {
        'id': {'in': ids},
      },
      limit: ids.length,
      depth: 0,
    );
    return {for (final lo in resp.docs) lo.id: lo};
  }

  /// Full activity plans for all the quest's LOs at its target language (one
  /// read), each paired with the LO ids it satisfies (for grouping).
  static Future<List<({ActivityPlanModel plan, List<String> refs})>>
  _questActivityPlans(QuestPlan quest) async {
    final loIds = quest.learningObjectiveIds;
    if (loIds.isEmpty) return const [];
    final resp = await _client().find<Map<String, dynamic>>(
      _activities,
      (json) => json,
      where: _loAtL2Where(loIds, quest.targetLanguage),
      limit: 200,
      depth: 0,
    );
    final entries = resp.docs
        .map(
          (doc) => (
            plan: activityPlanFromV2(doc),
            refs: ((doc['learningObjectiveRefs'] as List? ?? const [])
                .map((e) => e is Map ? e['id'] as String : e as String)
                .toList()),
          ),
        )
        .toList();
    // Resolve all plans' media upload_ids → CDN URLs in one batched read.
    final resolved = await _withResolvedMedia(
      entries.map((e) => e.plan).toList(),
    );
    return [
      for (var i = 0; i < entries.length; i++)
        (plan: resolved[i], refs: entries[i].refs),
    ];
  }

  /// Process-lifetime cache of resolved outlines, keyed by quest id, so
  /// switching back to a course's plan doesn't re-spin. In-memory (not
  /// GetStorage) because [QuestOutline] carries session-scoped media CDN URLs —
  /// same reasoning as `ActivityPlanRepo`'s in-memory resolve cache.
  static final Map<String, QuestOutline> _outlineCache = {};
  static final Map<String, Future<QuestOutline>> _outlineInflight = {};

  /// The full outline: quest + objective groups (LOs in order, each with its
  /// matching activities). Cached per quest id; concurrent calls for the same
  /// quest share one in-flight read. Pass [forceRefresh] to bypass the cache.
  static Future<QuestOutline> outline(
    String questId, {
    bool forceRefresh = false,
  }) {
    if (!forceRefresh) {
      final cached = _outlineCache[questId];
      if (cached != null) return Future.value(cached);
      final inflight = _outlineInflight[questId];
      if (inflight != null) return inflight;
    }
    final future = _buildOutline(questId)
        .then((outline) {
          _outlineCache[questId] = outline;
          return outline;
        })
        .whenComplete(() => _outlineInflight.remove(questId));
    _outlineInflight[questId] = future;
    return future;
  }

  /// Drop the cached outline for [questId] (e.g. after a course edit).
  static void invalidateOutline(String questId) {
    _outlineCache.remove(questId);
    _outlineInflight.remove(questId);
  }

  /// Drop all cached outlines (e.g. on logout / account switch).
  static void clearOutlineCache() {
    _outlineCache.clear();
    _outlineInflight.clear();
  }

  /// Build a fresh outline — three reads (the quest, then the LO-text batch and
  /// the activities query in parallel). Uncached; callers use [outline].
  static Future<QuestOutline> _buildOutline(String questId) async {
    final quest = await QuestRepo.quest(questId);

    // LO text and activities both depend only on the quest — run in parallel.
    final losFuture = QuestRepo.learningObjectives(quest.learningObjectiveIds);
    final actsFuture = QuestRepo._questActivityPlans(quest);
    final los = await losFuture;
    final acts = await actsFuture;

    final byLo = <String, List<QuestActivity>>{};
    for (final a in acts) {
      final qa = QuestActivity(activityId: a.plan.activityId, plan: a.plan);
      for (final ref in a.refs) {
        (byLo[ref] ??= []).add(qa);
      }
    }

    final groups = quest.sequence
        .map(
          (step) => QuestObjectiveGroup(
            objective: los[step.objective.id] ?? step.objective,
            activities: byLo[step.objective.id] ?? const [],
          ),
        )
        .toList();
    return QuestOutline(quest: quest, groups: groups);
  }

  // The single-activity read moved to ActivityPlanRepo (choreo GET /v2/activity,
  // cached via BaseRepo) — see activity_plan_repo.dart.

  /// Thin map pins for a single quest — its LOs' activities at its L2, with
  /// coordinates (one read after resolving the quest's LO ids).
  static Future<List<QuestActivityCard>> questPins(String questId) async {
    final q = await quest(questId);
    final loIds = q.learningObjectiveIds;
    if (loIds.isEmpty) return const [];
    final resp = await _client().find(
      _activities,
      (json) => QuestActivityCard.fromJson(json),
      where: _loAtL2Where(loIds, q.targetLanguage),
      select: _pinSelect,
      limit: 200,
      depth: 0,
    );
    return resp.docs.where((card) => card.point != null).toList();
  }

  /// Thin map pins built from activities' own coordinates (one read). Optional
  /// [l2] scopes to a single target language.
  static Future<List<QuestActivityCard>> mapActivities({String? l2}) async {
    final resp = await _client().find(
      _activities,
      (json) => QuestActivityCard.fromJson(json),
      where: {
        'and': [
          {
            'res.plan.coordinates': {'exists': true},
          },
          if (l2 != null)
            {
              'res.plan.l2': {'equals': l2},
            },
        ],
      },
      select: _pinSelect,
      limit: 500,
      depth: 0,
    );
    return resp.docs.where((card) => card.point != null).toList();
  }
}

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/features/activity_sessions/activity_media_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/course_plans/payload_client/payload_client.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/activity_v2_mapper.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class MissingQuestException implements Exception {}

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

  /// Project this outline into the pure [CourseLoOutline] the progression gate
  /// consumes: the quest's ordered objective ids, and per objective the set of
  /// activity ids that satisfy it. [starsToUnlock] carries the course's teacher
  /// override (defaults to the standard threshold). The single home for this
  /// mapping — the joined-course cache and the activity-session lock both use it.
  CourseLoOutline toCourseLoOutline({
    int starsToUnlock = kDefaultStarsToUnlockObjective,
  }) => CourseLoOutline(
    orderedLoIds: quest.learningObjectiveIds,
    activityIdsByLo: {
      for (final group in groups)
        group.objective.id: group.activities.map((a) => a.activityId).toSet(),
    },
    starsToUnlock: starsToUnlock,
  );
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
  static const String _questPlansKey = 'quest-plans';
  static const String _learningObjectivesKey = 'learning-objectives';
  static const String _activitiesKey = 'activities-v2';

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

  static PayloadClient _client() => PayloadClient(
    baseUrl: Environment.cmsApi,
    accessToken: MatrixState.pangeaController.userController.accessToken,
  );

  /// The quest with its ordered Learning Objective ids (one read). LO text is
  /// NOT populated by depth (Payload leaves the relationship-in-array a bare
  /// id), so [_learningObjectives] resolves it in a separate batch read.
  static Future<Result<QuestPlan>> quest(String questId) async {
    try {
      final quest = await _client().findById(
        _questPlansKey,
        questId,
        (json) => QuestPlan.fromJson(json),
      );
      return Result.value(quest);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"quest_id": questId});
      if (e is Response && e.statusCode == 404) {
        return Result.error(MissingQuestException());
      }
      return Result.error(e);
    }
  }

  /// The full Learning Objectives for [ids], resolved in one batched read.
  static Future<Result<Map<String, LearningObjective>>> _learningObjectives(
    List<String> ids,
  ) async {
    try {
      if (ids.isEmpty) return Result.value(const {});
      final resp = await _client().find(
        _learningObjectivesKey,
        (json) => LearningObjective.fromJson(json),
        where: {
          'id': {'in': ids},
        },
        limit: ids.length,
        depth: 0,
      );
      return Result.value({for (final lo in resp.docs) lo.id: lo});
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"lo_ids": ids});
      return Result.error(e);
    }
  }

  /// The activity's own Learning Objective ids — a thin, select-projected read
  /// (no plan body, no media) used to decide which joined courses a new session
  /// is shared into: its LOs intersected with each course's quest objectives.
  /// See [ActivityCourseResolver] and activities.instructions.md.
  static Future<Result<List<String>>> activityLearningObjectiveRefs(
    String activityId,
  ) async {
    try {
      final resp = await _client().find<Map<String, dynamic>>(
        _activitiesKey,
        (json) => json,
        where: {
          'id': {'equals': activityId},
        },
        select: {'learningObjectiveRefs': true},
        limit: 1,
        depth: 0,
      );
      if (resp.docs.isEmpty) return Result.value(const []);

      final entry = resp.docs.first['learningObjectiveRefs'] as List?;
      if (entry == null) return Result.value(const []);

      final response = entry
          .map((e) => e is Map ? e['id'] as String : e as String)
          .toList();

      return Result.value(response);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"activity_id": activityId});
      return Result.error(e);
    }
  }

  // The single-activity read moved to ActivityPlanRepo (choreo GET /v2/activity,
  // cached via BaseRepo) — see activity_plan_repo.dart.
  /// Thin map pins for a single quest — its LOs' activities at its L2, with
  /// coordinates (one read after resolving the quest's LO ids).
  static Future<Result<List<QuestActivityCard>>> questActivityCards(
    List<String> learningObjectiveIds,
    String targetLanguage,
  ) async {
    if (learningObjectiveIds.isEmpty) return Result.value(const []);
    try {
      final resp = await _client().find(
        _activitiesKey,
        (json) => QuestActivityCard.fromJson(json),
        where: _loAtL2Where(learningObjectiveIds, targetLanguage),
        select: _pinSelect,
        limit: 200,
        depth: 0,
      );
      final filtered = resp.docs.where((card) => card.point != null).toList();
      return Result.value(filtered);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "learning_objective_ids": learningObjectiveIds,
          "target_language": targetLanguage,
        },
      );
      return Result.error(e);
    }
  }

  /// Full activity plans for all the quest's LOs at its target language (one
  /// read), each paired with the LO ids it satisfies (for grouping).
  static Future<Result<List<({ActivityPlanModel plan, List<String> refs})>>>
  _questActivityPlans(QuestPlan quest) async {
    try {
      final loIds = quest.learningObjectiveIds;
      if (loIds.isEmpty) return Result.value(const []);
      final resp = await _client().find<Map<String, dynamic>>(
        _activitiesKey,
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

      return Result.value([
        for (var i = 0; i < entries.length; i++)
          (plan: resolved[i], refs: entries[i].refs),
      ]);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      return Result.error(e);
    }
  }

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

  /// Process-lifetime cache of resolved outlines, keyed by quest id, so
  /// switching back to a course's plan doesn't re-spin. In-memory (not
  /// GetStorage) because [QuestOutline] carries session-scoped media CDN URLs —
  /// same reasoning as `ActivityPlanRepo`'s in-memory resolve cache.
  static final Map<String, Result<QuestOutline>> _outlineCache = {};
  static final Map<String, Future<Result<QuestOutline>>> _outlineInflight = {};

  /// The full outline: quest + objective groups (LOs in order, each with its
  /// matching activities). Cached per quest id; concurrent calls for the same
  /// quest share one in-flight read. Pass [forceRefresh] to bypass the cache.
  static Future<Result<QuestOutline>> outline(
    String questId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _outlineCache[questId];
      if (cached != null) return Future.value(cached);
      final inflight = _outlineInflight[questId];
      if (inflight != null) return inflight;
    }

    final future = _buildOutline(questId);
    _outlineInflight[questId] = future;

    final outline = await future;

    _outlineCache[questId] = outline;
    _outlineInflight.remove(questId);

    return outline;
  }

  /// Build a fresh outline — three reads (the quest, then the LO-text batch and
  /// the activities query in parallel). Uncached; callers use [outline].
  static Future<Result<QuestOutline>> _buildOutline(String questId) async {
    try {
      final result = await QuestRepo.quest(questId);
      final quest = result.result;
      if (quest == null) {
        return Result.error(result.error ?? MissingQuestException());
      }

      // LO text and activities both depend only on the quest — run in parallel.
      final losFuture = _learningObjectives(quest.learningObjectiveIds);
      final actsFuture = _questActivityPlans(quest);

      final learningObjectivesResult = await losFuture;
      final learningObjectives = learningObjectivesResult.result;
      if (learningObjectives == null) {
        return Result.error(
          learningObjectivesResult.error ??
              "Failed to fetch learning objectives",
        );
      }

      final activitiesResult = await actsFuture;
      final activities = activitiesResult.result;
      if (activities == null) {
        return Result.error(
          activitiesResult.error ?? "Failed to fetch activities",
        );
      }

      final byLo = <String, List<QuestActivity>>{};
      for (final a in activities) {
        final qa = QuestActivity(activityId: a.plan.activityId, plan: a.plan);
        for (final ref in a.refs) {
          (byLo[ref] ??= []).add(qa);
        }
      }

      final groups = quest.sequence
          .map(
            (step) => QuestObjectiveGroup(
              objective:
                  learningObjectives[step.objective.id] ?? step.objective,
              activities: byLo[step.objective.id] ?? const [],
            ),
          )
          .toList();

      return Result.value(QuestOutline(quest: quest, groups: groups));
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"quest_id": questId});
      return Result.error(e);
    }
  }
}

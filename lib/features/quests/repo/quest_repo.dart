import 'dart:convert';

import 'package:flutter/foundation.dart';

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
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class MissingQuestException implements Exception {}

/// The single home of the per-course activity-pin rule (org quests doc,
/// client#7748): which of a Mission's [available] activity ids count when the
/// course pins [pinned] for it. Fail-open by design — no pin, an empty pin, or
/// a pin whose ids are all stale (no intersection) yields [available]
/// unchanged, so a pin can never make a Mission unsatisfiable. Consumers:
/// [QuestOutline.restrictedTo] and the course-scoped map's marker filter.
Set<String> effectivePinnedActivityIds(
  Set<String> available,
  List<String>? pinned,
) {
  if (pinned == null || pinned.isEmpty) return available;
  final intersection = available.intersection(pinned.toSet());
  return intersection.isEmpty ? available : intersection;
}

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

  /// A copy with each pinned Mission's activities filtered to its pinned set —
  /// per-course activity pinning (org quests doc; client#7748). A PURE COPY:
  /// the outline cache is shared across courses referencing the same quest, so
  /// the same quest can run restricted in one course and open in another only
  /// because this never mutates the source.
  ///
  /// Fail-open rules (a pin can never make a Mission unsatisfiable): a Mission
  /// with no pin entry or an empty pinned list is unrestricted; pinned ids are
  /// intersected with the Mission's actual activities, and an intersection
  /// that comes up empty (all pins stale) falls back to unrestricted.
  QuestOutline restrictedTo(Map<String, List<String>>? pinnedByObjective) {
    if (pinnedByObjective == null || pinnedByObjective.isEmpty) return this;
    return QuestOutline(
      quest: quest,
      groups: [
        for (final group in groups)
          _restrictGroup(group, pinnedByObjective[group.objective.id]),
      ],
    );
  }

  static QuestObjectiveGroup _restrictGroup(
    QuestObjectiveGroup group,
    List<String>? pinned,
  ) {
    final available = group.activities.map((a) => a.activityId).toSet();
    final allowed = effectivePinnedActivityIds(available, pinned);
    if (allowed.length == available.length) return group;
    return QuestObjectiveGroup(
      objective: group.objective,
      activities: group.activities
          .where((a) => allowed.contains(a.activityId))
          .toList(),
    );
  }

  /// Project this outline into the pure [CourseLoOutline] the progression gate
  /// consumes: the quest's ordered objective ids, and per objective the set of
  /// activity ids that satisfy it. [starsToUnlock] carries the course's teacher
  /// override (defaults to the standard threshold). The single home for this
  /// mapping — the joined-course cache and the activity-session lock both use it.
  CourseLoOutline toCourseLoOutline({
    int starsToUnlock = kDefaultStarsToUnlockObjective,
  }) => CourseLoOutline(
    // The quest id serves as the scoping key here — right for scoped/preview
    // outlines that have no room. The joined-course cache re-keys courseId to
    // the course room id (unique per course) so two courses built from one
    // quest stay distinct (#8087); questId survives that re-key for the
    // world-map band's per-quest dedupe.
    courseId: quest.id,
    questId: quest.id,
    orderedLoIds: quest.learningObjectiveIds,
    activityIdsByLo: {
      for (final group in groups)
        group.objective.id: group.activities.map((a) => a.activityId).toSet(),
    },
    starsToUnlock: starsToUnlock,
    earnableByActivity: {
      for (final group in groups)
        for (final a in group.activities) a.activityId: a.plan.earnableStars,
    },
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

  /// Parse the choreo `GET /choreo/quests/{id}/activities` body into its raw
  /// activity entries (`{plan, version_id, learning_objective_refs}` maps).
  /// Canonical-only filtering, translation-row exclusion, and hidden/private
  /// gating all happen server-side now — the client no longer builds an
  /// activities-v2 `where` at all (see activities.instructions.md
  /// § Ownership, visibility, and removal).
  @visibleForTesting
  static List<Map<String, dynamic>> questActivityEntriesFromJson(
    dynamic decoded,
  ) {
    if (decoded is! Map) return const [];
    final list = decoded['activities'];
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map) e.cast<String, dynamic>(),
    ];
  }

  /// Adapt one choreo entry to the CMS-doc shape [QuestActivityCard.fromJson]
  /// and [activityPlanFromV2] already parse, so both consumers keep one parser.
  @visibleForTesting
  static Map<String, dynamic> cmsDocShapeFromEntry(Map<String, dynamic> entry) {
    return {
      'res': {'plan': entry['plan']},
      'learningObjectiveRefs': entry['learning_objective_refs'] ?? const [],
      // The plan's canonical content-signature, so a session opened straight
      // from the outline pins its version without a refetch (the same token
      // GET /v2/activity/{id} returns).
      'version_id': entry['version_id'],
    };
  }

  /// The quest's activities from the choreo course listing — the
  /// membership-aware read that may include the quest owner's private
  /// activities when [courseRoomId] names a course the caller has joined.
  static Future<Result<List<Map<String, dynamic>>>> _questActivityEntries(
    String questId, {
    String? courseRoomId,
  }) async {
    try {
      final uri = Uri.parse(PApiUrls.questActivities(questId)).replace(
        queryParameters: {
          if (courseRoomId != null && courseRoomId.isNotEmpty)
            'course_room_id': courseRoomId,
        },
      );
      final response = await Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
      ).get(url: uri.toString());
      if (response.statusCode != 200) {
        return Result.error(
          'quest activities fetch failed (${response.statusCode})',
        );
      }
      return Result.value(
        questActivityEntriesFromJson(jsonDecode(response.body)),
      );
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"quest_id": questId});
      return Result.error(e);
    }
  }

  /// Keep the first row per `activity_id`. Degraded data (a duplicate
  /// canonical, or an orphaned translation slipping past a filter) must never
  /// surface the same activity twice: duplicate ids render duplicate cards
  /// and, worse, duplicate `ValueKey`s in the world-map marker Stack — a hard
  /// crash (#7604). Last line of defense; [loAtL2Where] is the primary filter.
  @visibleForTesting
  static List<T> dedupeByActivityId<T>(List<T> rows, String Function(T) idOf) {
    final seen = <String>{};
    return [
      for (final row in rows)
        if (seen.add(idOf(row))) row,
    ];
  }

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
      if (e is Response && e.statusCode == 404) {
        return Result.error(MissingQuestException());
      }

      ErrorHandler.logError(e: e, s: s, data: {"quest_id": questId});
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

  /// The activity's own Learning Objective ids, used to decide which joined
  /// courses a new session is shared into: its LOs intersected with each
  /// course's quest objectives. Reads through the choreo activity fetch
  /// (which projects `learning_objective_refs`) rather than CMS-direct —
  /// end-user CMS credentials can no longer read hidden rows, and this
  /// attribution must keep working for sessions on hidden activities
  /// (activities.instructions.md § Ownership, visibility, and removal).
  /// See [ActivityCourseResolver].
  static Future<Result<List<String>>> activityLearningObjectiveRefs(
    String activityId,
  ) async {
    try {
      final response = await Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
      ).get(url: PApiUrls.activityById(activityId));
      // A removed activity reads as "no refs", matching the previous
      // CMS-direct empty-find behavior.
      if (response.statusCode == 404) return Result.value(const []);
      if (response.statusCode != 200) {
        return Result.error('activity fetch failed (${response.statusCode})');
      }
      final decoded = jsonDecode(response.body);
      final refs = decoded is Map
          ? decoded['learning_objective_refs'] as List?
          : null;
      return Result.value((refs ?? const []).map((e) => e as String).toList());
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"activity_id": activityId});
      return Result.error(e);
    }
  }

  // The single-activity read moved to ActivityPlanRepo (choreo GET /v2/activity,
  // cached via BaseRepo) — see activity_plan_repo.dart.
  /// Map pins for a single quest — its activities with coordinates, via the
  /// choreo course listing. [courseRoomId] admits the quest owner's private
  /// activities when the caller is a joined member of that course.
  static Future<Result<List<QuestActivityCard>>> questActivityCards(
    String questId, {
    String? courseRoomId,
  }) async {
    final entriesResult = await _questActivityEntries(
      questId,
      courseRoomId: courseRoomId,
    );
    final entries = entriesResult.result;
    if (entries == null) {
      return Result.error(
        entriesResult.error ?? "Failed to fetch quest activities",
      );
    }
    final cards = entries
        .map((e) => QuestActivityCard.fromJson(cmsDocShapeFromEntry(e)))
        .where((card) => card.point != null)
        .toList();
    return Result.value(dedupeByActivityId(cards, (c) => c.activityId));
  }

  /// Full activity plans for the quest (one choreo read), each paired with
  /// the LO ids it satisfies (for grouping). [courseRoomId] admits the quest
  /// owner's private activities when the caller is a joined member.
  static Future<Result<List<({ActivityPlanModel plan, List<String> refs})>>>
  _questActivityPlans(String questId, {String? courseRoomId}) async {
    try {
      final entriesResult = await _questActivityEntries(
        questId,
        courseRoomId: courseRoomId,
      );
      final rawEntries = entriesResult.result;
      if (rawEntries == null) {
        return Result.error(
          entriesResult.error ?? "Failed to fetch quest activities",
        );
      }
      final entries = dedupeByActivityId(
        rawEntries
            .map(
              (e) => (
                plan: activityPlanFromV2(cmsDocShapeFromEntry(e)),
                refs: ((e['learning_objective_refs'] as List? ?? const [])
                    .map((x) => x as String)
                    .toList()),
              ),
            )
            .toList(),
        (e) => e.plan.activityId,
      );

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

  /// Process-lifetime cache of resolved outlines, keyed by quest id + course
  /// room (a course-member read can carry private activities a plain read
  /// doesn't, so the two must not share a cache row). In-memory (not
  /// GetStorage) because [QuestOutline] carries session-scoped media CDN URLs —
  /// same reasoning as `ActivityPlanRepo`'s in-memory resolve cache.
  ///
  /// Holds SUCCESSES ONLY: caching an error would pin a transient failure (or
  /// a since-restored quest) for the process lifetime, so every retry — the
  /// world map's empty-cache self-heal, a panel reopen — would replay the
  /// stale error instead of ever recovering (#8083).
  static final Map<String, Result<QuestOutline>> _outlineCache = {};
  static final Map<String, Future<Result<QuestOutline>>> _outlineInflight = {};

  /// Test seam for [outline]: replaces [_buildOutline] when set, so the
  /// cache-on-success / never-cache-errors contract is testable without the
  /// networked read layer.
  @visibleForTesting
  static Future<Result<QuestOutline>> Function(
    String questId, {
    String? courseRoomId,
  })?
  debugBuildOutline;

  @visibleForTesting
  static void resetOutlineCacheForTest() {
    _outlineCache.clear();
    _outlineInflight.clear();
  }

  /// The full outline: quest + objective groups (LOs in order, each with its
  /// matching activities). Successes are cached per (quest id, course room);
  /// errors are returned but never cached (see [_outlineCache]). Concurrent
  /// calls for the same key share one in-flight read. [courseRoomId] admits
  /// the quest owner's private activities when the caller is a joined member
  /// of that course. Pass [forceRefresh] to bypass the cache.
  static Future<Result<QuestOutline>> outline(
    String questId, {
    String? courseRoomId,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '$questId|${courseRoomId ?? ''}';
    if (!forceRefresh) {
      final cached = _outlineCache[cacheKey];
      if (cached != null) return Future.value(cached);
      final inflight = _outlineInflight[cacheKey];
      if (inflight != null) return inflight;
    }

    final future = (debugBuildOutline ?? _buildOutline)(
      questId,
      courseRoomId: courseRoomId,
    );
    _outlineInflight[cacheKey] = future;

    final outline = await future;

    if (outline.isValue) {
      _outlineCache[cacheKey] = outline;
    }
    _outlineInflight.remove(cacheKey);

    return outline;
  }

  /// Build a fresh outline — three reads (the quest, then the LO-text batch and
  /// the activities query in parallel). Uncached; callers use [outline].
  static Future<Result<QuestOutline>> _buildOutline(
    String questId, {
    String? courseRoomId,
  }) async {
    try {
      final result = await QuestRepo.quest(questId);
      final quest = result.result;
      if (quest == null) {
        return Result.error(result.error ?? MissingQuestException());
      }

      // LO text and activities both depend only on the quest — run in parallel.
      final losFuture = _learningObjectives(quest.learningObjectiveIds);
      final actsFuture = _questActivityPlans(
        questId,
        courseRoomId: courseRoomId,
      );

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

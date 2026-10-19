import 'package:latlong2/latlong.dart';

/// A thin goal on a map pin: the goal's stable identity and role mapping, with
/// the localized `goal` copy dropped. Carried by the bbox card so the map can
/// show per-role star progress (earned/total) without hydrating the full plan —
/// completion is matched on [goalSlug] first (the orchestrator's stable award
/// key), then [id] as a legacy fallback, per role. See world-map.instructions.md.
class ActivityCardGoal {
  /// The CMS goals array-row id — a legacy completion-match fallback. Optional:
  /// null on goals minted before ids were surfaced.
  final String? id;

  /// Content-derived award identity the orchestrator scores on (survives owner
  /// edits and translation). Null on legacy/unmigrated goals.
  final String? goalSlug;

  /// Ids of the roles that share this goal (`Role.role_id`), so a role's total
  /// is the goals whose [roleIds] contains it.
  final List<String> roleIds;

  /// `opener` | `buildup` | `finale`.
  final String? phase;

  const ActivityCardGoal({
    this.id,
    this.goalSlug,
    this.roleIds = const [],
    this.phase,
  });

  factory ActivityCardGoal.fromJson(Map<String, dynamic> json) =>
      ActivityCardGoal(
        id: json['id'] as String?,
        goalSlug: json['goal_slug'] as String?,
        roleIds: ((json['role_ids'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
        phase: json['phase'] as String?,
      );
}

/// A thin activity projection for lists and map pins, read from `activities-v2`
/// with a field projection (no full plan body). The full `ActivityPlanModel`
/// is fetched only when an activity is opened.
///
/// Beyond the search/relevance fields, the bbox card carries cheap,
/// **non-localized** structural metadata so the map can rank and show progress
/// without a full-plan hydration: [roleIds]/[roleCount] (the multi-person
/// deprioritize, #7435), thin [goals] (per-role progress), [mode], the
/// [ratingAverage]/[ratingCount], [originalL1], and the row's [starter] flag.
/// The heavy, localized content (role personas, goal copy, vocab, media) stays
/// off the pin.
class QuestActivityCard {
  final String activityId;
  final String title;
  final String l2;

  /// `res.plan.coordinates` as stored: `[longitude, latitude]`, or null when
  /// the activity is unplaced.
  final List<double>? coordinates;

  /// Learning-objective ids this activity satisfies; lets the repo group cards
  /// under the quest's objectives without a second read, and lets the world map
  /// compute relevance banding. Carried by both the CMS pin read and the
  /// choreographer bbox card. See world-map.instructions.md.
  final List<String> learningObjectiveRefs;

  /// Content-search + CEFR-filter fields, populated only for World map pins read
  /// via the bbox endpoint (the projected CMS pin read leaves them null). Used
  /// by the map search box (title/description/learningObjective) and the CEFR
  /// filter chip. Text arrives in the display language the bbox request asked
  /// for (`l1`), canonical per card where no translation row exists yet
  /// (#8398) — so [matchesQuery] must stay tolerant of a mixed set. These are
  /// search-matching fields, never rendered on a pin.
  final String? description;
  final String? learningObjective;
  final String? cefr;

  /// Number of roles (== the plan's role count). Drives the multi-person
  /// deprioritize for a new learner's first map (#7435). Null when the pin read
  /// did not project it (e.g. course-scoped CMS reads, or an older choreo).
  final int? roleCount;

  /// Role ids (`Role.role_id`) on this activity — localized names/personas
  /// dropped. Empty when not projected.
  final List<String> roleIds;

  /// Thin goals (`{id, goalSlug, roleIds, phase}`) for per-role star progress
  /// without hydrating the full plan. Empty when not projected.
  final List<ActivityCardGoal> goals;

  /// Conversation mode / format (Roleplay, Conversation, Debate, …),
  /// non-localized. Null when not projected.
  final String? mode;

  final double? ratingAverage;
  final int? ratingCount;

  /// The activity's source language of authoring (non-localized).
  final String? originalL1;

  /// Marked a **starter** on its row: the generic two-role A1 meet-and-greet a
  /// brand-new learner is pointed at first (org activities doc, "Starter
  /// activities"). Read from the top-level `starter` of both the bbox card and
  /// the course listing's entry ([starterFlagFrom]); false when the server
  /// does not send it, so the steer is inert until the content and server
  /// halves ship — except for the [temporaryStarterActivityIds] stopgap.
  final bool starter;

  /// TEMPORARY — remove with its uses once cms#504 and choreo#3383 are
  /// deployed and the four rows' `starter` flags are ticked.
  ///
  /// The four starter rows authored for pangeachat/.github#734, treated as
  /// starters while the server sends no `starter` field, so a working version
  /// can be shown before the CMS and choreo halves ship (the user's call,
  /// recorded on client#9562). A hard-coded id set is exactly what the org
  /// activities doc's starter design rules out; this one is tolerable only
  /// because `activity_id` is the env-stable content id the sync engine
  /// preserves, so the same four ids name the rows on staging and production.
  static const Set<String> temporaryStarterActivityIds = {
    'c7fc5fb3-7c62-44c9-bc93-840ecb703b81', // es — Hello in Plaza Mayor
    '256ffd18-637c-4b15-b591-9b735e118f61', // en — First Hello by the Fountain
    'f4f2b1fb-8c6d-4a69-b2ae-4091981b4ff9', // fr — First Hello by the Pond
    '8dd18ff7-e7ba-4ccd-bb04-765f36693766', // de — Hello at the Brandenburg Gate
  };

  /// The row's starter flag from [json]'s top-level `starter`: the server's
  /// value whenever it sends one, else the [temporaryStarterActivityIds]
  /// stopgap. The one place every read of the flag goes through — both card
  /// parsers and the course outline's [QuestActivity] — so the stopgap is
  /// removed in one edit.
  static bool starterFlagFrom(Map<String, dynamic> json, String activityId) {
    final flag = json['starter'];
    if (flag is bool) return flag;
    return temporaryStarterActivityIds.contains(activityId);
  }

  const QuestActivityCard({
    required this.activityId,
    required this.title,
    required this.l2,
    required this.coordinates,
    required this.learningObjectiveRefs,
    this.description,
    this.learningObjective,
    this.cefr,
    this.roleCount,
    this.roleIds = const [],
    this.goals = const [],
    this.mode,
    this.ratingAverage,
    this.ratingCount,
    this.originalL1,
    this.starter = false,
  });

  /// True when [query] matches the activity's searchable text (title +
  /// description + learning objective), case-insensitive. Empty query matches.
  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        (description?.toLowerCase().contains(q) ?? false) ||
        (learningObjective?.toLowerCase().contains(q) ?? false);
  }

  /// `(lat, lng)` for flutter_map, or null when unplaced.
  LatLng? get point => (coordinates != null && coordinates!.length == 2)
      ? LatLng(coordinates![1], coordinates![0])
      : null;

  /// Per-role goal counts from the thin [goals] (a goal shared across roles
  /// counts once for each). Empty when the card carries no thin goals.
  Map<String, int> get goalCountByRole {
    final counts = <String, int>{};
    for (final g in goals) {
      for (final r in g.roleIds) {
        counts[r] = (counts[r] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// The activity's display star total from the thin [goals] — no plan
  /// hydration. Generation keeps per-role goal counts uniform; when they
  /// disagree this falls back to the **min** across roles, mirroring
  /// [ActivityPlanModel.earnableStars] (decided 2026-07-18 — supersedes the
  /// "fallback to average/greatest" line in the Figma Pins-v6 annotation; see
  /// world-map.instructions.md, "Goal Progress"). Null when the card carries
  /// no thin goals (an older choreo) — callers fall back to the hydrated plan.
  int? get thinStarsTotal {
    final counts = goalCountByRole.values;
    if (counts.isEmpty) return null;
    return counts.reduce((a, b) => b < a ? b : a);
  }

  factory QuestActivityCard.fromJson(Map<String, dynamic> json) {
    final plan =
        ((json['res'] as Map?)?['plan'] as Map?)?.cast<String, dynamic>() ??
        const {};
    final coords = plan['coordinates'];
    final refs = (json['learningObjectiveRefs'] as List?) ?? const [];
    final rolesJson = plan['roles'] as List?;
    final activityId = (plan['activity_id'] ?? json['id']) as String;
    return QuestActivityCard(
      activityId: activityId,
      title: (plan['title'] ?? '') as String,
      l2: (plan['l2'] ?? '') as String,
      coordinates: coords is List
          ? coords.map((e) => (e as num).toDouble()).toList()
          : null,
      learningObjectiveRefs: refs
          .map((e) => e is Map ? e['id'] as String : e as String)
          .toList(),
      // The CEFR level from the same `res.plan` node the full plan mapper reads
      // ([activityPlanFromV2]'s `plan['cefr_level']`), so a course-scoped card
      // shows its level on the large card and bands by it — the world-map bbox
      // card already carries this; the course path had simply dropped it (#8243).
      cefr: plan['cefr_level'] as String?,
      // Participant count == role count (the value activityPlanFromV2 derives
      // and the card shows), so a course-scoped pin can dim when the course
      // lacks enough members to start it. Null when roles weren't projected.
      roleCount: rolesJson?.length,
      starter: starterFlagFrom(json, activityId),
    );
  }

  /// Parse a choreographer `ActivityCard` (the `GET /v2/activities/bbox` shape):
  /// a flat card carrying content-search text, cefr, and the LO refs (a flat list
  /// of ids) the map needs for relevance banding.
  factory QuestActivityCard.fromBboxCard(Map<String, dynamic> json) {
    final coords = json['coordinates'];
    final refs = (json['learning_objective_refs'] as List?) ?? const [];
    final rolesJson = (json['roles'] as List?) ?? const [];
    final goalsJson = (json['goals'] as List?) ?? const [];
    final activityId = json['activity_id'] as String;
    return QuestActivityCard(
      activityId: activityId,
      title: (json['title'] ?? '') as String,
      l2: (json['l2'] ?? '') as String,
      coordinates: coords is List
          ? coords.map((e) => (e as num).toDouble()).toList()
          : null,
      learningObjectiveRefs: refs
          .map((e) => e is Map ? e['id'] as String : e as String)
          .toList(),
      description: json['description'] as String?,
      learningObjective: json['learning_objective'] as String?,
      cefr: json['cefr_level'] as String?,
      // Cheap non-localized structural metadata (drops role/goal copy). Absent
      // on an older choreo → null/empty, so the deprioritize + progress features
      // are simply inert until the server ships these fields.
      roleIds: rolesJson.map((r) => (r as Map)['role_id'] as String).toList(),
      roleCount: json.containsKey('roles') ? rolesJson.length : null,
      goals: goalsJson
          .map(
            (g) =>
                ActivityCardGoal.fromJson((g as Map).cast<String, dynamic>()),
          )
          .toList(),
      mode: json['mode'] as String?,
      ratingAverage: (json['rating_average'] as num?)?.toDouble(),
      ratingCount: json['rating_count'] as int?,
      originalL1: json['original_l1'] as String?,
      starter: starterFlagFrom(json, activityId),
    );
  }
}

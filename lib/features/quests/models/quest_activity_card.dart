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
/// [ratingAverage]/[ratingCount], and [originalL1]. The heavy, localized content
/// (role personas, goal copy, vocab, media) stays off the pin.
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
  /// filter chip.
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

  factory QuestActivityCard.fromJson(Map<String, dynamic> json) {
    final plan =
        ((json['res'] as Map?)?['plan'] as Map?)?.cast<String, dynamic>() ??
        const {};
    final coords = plan['coordinates'];
    final refs = (json['learningObjectiveRefs'] as List?) ?? const [];
    return QuestActivityCard(
      activityId: (plan['activity_id'] ?? json['id']) as String,
      title: (plan['title'] ?? '') as String,
      l2: (plan['l2'] ?? '') as String,
      coordinates: coords is List
          ? coords.map((e) => (e as num).toDouble()).toList()
          : null,
      learningObjectiveRefs: refs
          .map((e) => e is Map ? e['id'] as String : e as String)
          .toList(),
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
    return QuestActivityCard(
      activityId: json['activity_id'] as String,
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
    );
  }
}

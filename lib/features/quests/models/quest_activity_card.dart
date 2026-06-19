import 'package:latlong2/latlong.dart';

/// A thin activity projection for lists and map pins, read from `activities-v2`
/// with a field projection (no full plan body). The full `ActivityPlanModel`
/// is fetched only when an activity is opened.
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

  const QuestActivityCard({
    required this.activityId,
    required this.title,
    required this.l2,
    required this.coordinates,
    required this.learningObjectiveRefs,
    this.description,
    this.learningObjective,
    this.cefr,
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
    );
  }
}

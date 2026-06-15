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
  /// under the quest's objectives without a second read.
  final List<String> learningObjectiveRefs;

  const QuestActivityCard({
    required this.activityId,
    required this.title,
    required this.l2,
    required this.coordinates,
    required this.learningObjectiveRefs,
  });

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
}

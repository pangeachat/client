/// One dosage session-outcome signal, emitted when a completed activity session
/// banks its stars (the archive moment). The wire body is the verbatim [toJson]
/// under `outcomes[]`; the BFF ingest is `extra="forbid"`, so this carries
/// EXACTLY the six contract keys and no `sender` (bound server-side).
///
/// Every field the client supplies is a HINT: the server re-verifies the awards
/// against the session room's bot-authored state and re-derives course/LO
/// attribution before a row is trusted.
class DosageSessionOutcome {
  final String sessionRoomId;
  final String activityId;
  final String? sourceCourseId;
  final List<String> loRefs;

  /// The learner's completed goals keyed by goal slug (id fallback), as the
  /// client sees them from `pangea.orchestrator_awarded_goals` — one star per
  /// completed goal, the same star model the client renders.
  final Map<String, int> starsByGoalSlug;
  final DateTime completedAt;

  const DosageSessionOutcome({
    required this.sessionRoomId,
    required this.activityId,
    required this.sourceCourseId,
    required this.loRefs,
    required this.starsByGoalSlug,
    required this.completedAt,
  });

  Map<String, dynamic> toJson() => {
    "session_room_id": sessionRoomId,
    "activity_id": activityId,
    "source_course_id": sourceCourseId,
    "lo_refs": loRefs,
    "stars_by_goal_slug": starsByGoalSlug,
    "completed_at": completedAt.toUtc().toIso8601String(),
  };
}

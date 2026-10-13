/// One-shot hand-off from an activity plan's back arrow to the full course
/// plan it returns to: the activity the learner just left, so the plan that
/// mounts scrolls that activity's Mission into view (routing.instructions.md,
/// "How each surface opens" → Activity plan; #9367).
///
/// Scroll position is view state, so it rides here rather than in the URL.
/// Keyed by course so a plan for another course can never take it.
class CoursePlanReturn {
  CoursePlanReturn._();

  static String? _courseId;
  static String? _activityId;

  static void arm({required String courseId, required String activityId}) {
    _courseId = courseId;
    _activityId = activityId;
  }

  /// The activity to reveal in [courseId]'s full plan, or null. Clears any
  /// pending hand-off, so it is taken at most once.
  static String? take(String courseId) {
    final activityId = _courseId == courseId ? _activityId : null;
    _courseId = null;
    _activityId = null;
    return activityId;
  }
}

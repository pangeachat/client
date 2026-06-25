class ActivitySessionConstants {
  static const String plusIconPath = "add_icon.svg";
  static const String crayonIconPath = "make_your_own_icon.svg";
  static const String modeImageFileStart = "activityplanner_mode_";
  static const String makeActivityAssetPath = "Spark+imaginative.png";
  static const String endActivityAssetPath = "EndActivityMsg.png";

  static const String activityPlanRequest = 'req';
  static const String activityPlanTitle = 'title';
  static const String description = 'description';
  static const String duration = 'duration';
  static const String activityPlanLocation = 'location';
  static const String activityPlanLearningObjective = 'learning_objective';
  static const String activityPlanInstructions = 'instructions';
  static const String activityPlanVocab = 'vocab';
  static const String activityPlanImageURL = 'image_url';
  static const String activityPlanMedia = 'media';
  static const String activityId = 'activity_id';
  static const String activityPlanEndAt = 'end_at';

  /// Reference-shape `pangea.activity_plan` state event fields. The session
  /// room stores `{ activity_id, version_id, source_course_id? }` and the plan
  /// body is fetched live from CMS — see activities.instructions.md.
  static const String versionId = 'version_id';
  static const String sourceCourseId = 'source_course_id';
  // Pin-resolution outcome carried alongside the plan for analytics: whether
  // the pinned version was evicted (latest served instead) and why it degraded.
  static const String usedFallbackVersion = 'used_fallback_version';
  static const String fallbackCause = 'fallback_cause';

  static const String activityRequestTopic = 'topic';
  static const String activityRequestObjective = 'objective';
  static const String activityRequestMedia = 'media';
  static const String activityRequestCefrLevel = 'activity_cefr_level';
  static const String activityRequestLanguageOfInstructions =
      'language_of_instructions';
  static const String activityRequestCount = 'count';
  static const String activityRequestNumberOfParticipants =
      'number_of_participants';

  static String goalMenuStarTargetId(String goalId) =>
      "goal-display-star-$goalId";
}

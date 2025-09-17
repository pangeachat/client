class PangeaEventTypes {
  static const languageSettings = "pangea.class";

  static const transcript = "pangea.transcript";

  static const rules = "p.rules";

  // static const studentAnalyticsSummary = "pangea.usranalytics";
  static const summaryAnalytics = "pangea.summaryAnalytics";
  static const construct = "pangea.construct";
  static const userSetLemmaInfo = "p.user_lemma_info";
  static const constructSummary = "pangea.construct_summary";
  static const userChosenEmoji = "p.emoji";

  static const translation = "pangea.translation";
  static const tokens = "pangea.tokens";
  static const choreoRecord = "pangea.record";
  static const representation = "pangea.representation";
  static const sttTranslation = "pangea.stt_translation";

  // static const vocab = "p.vocab";
  static const roomInfo = "pangea.roomtopic";

  static const audio = "p.audio";
  static const botOptions = "pangea.bot_options";
  static const capacity = "pangea.capacity";

  static const activityPlan = "pangea.activity_plan";
  static const activityRole = "pangea.activity_roles";
  static const activitySummary = "pangea.activity_summary";

  static const userAge = "pangea.user_age";

  static const String report = 'm.report';
  static const textToSpeechRule = "p.rule.text_to_speech";

  /// A request to the server to generate activities
  static const activityRequest = "pangea.activity_req";

  /// A practice activity that is related to a message
  static const pangeaActivity = "pangea.activity_res";

  /// A record of completion of an activity. There
  /// can be one per user per activity.
  static const activityRecord = "pangea.activity_completion";

  /// Profile information related to a user's analytics
  static const profileAnalytics = "pangea.analytics_profile";
  static const profileActivities = "pangea.activities_profile";
  static const activityRoomIds = "pangea.activity_room_ids";

  /// Relates to course plans
  static const coursePlan = "pangea.course_plan";
  static const courseUser = "p.course_user";
}

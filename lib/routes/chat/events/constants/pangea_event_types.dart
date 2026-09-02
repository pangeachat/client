class PangeaEventTypes {
  static const construct = "pangea.construct";
  static const userSetLemmaInfo = "p.user_lemma_info";
  static const activityRoomIds = "pangea.activity_room_ids";
  static const analyticsStatus = "pangea.analytics.status";

  static const tokens = "pangea.tokens";
  static const choreoRecord = "pangea.record";
  static const representation = "pangea.representation";
  static const sttTranslation = "pangea.stt_translation";
  static const textToSpeech = "pangea.text_to_speech";

  /// A call that happened in this room: when, how long, and whether it carried
  /// video. Written once when the call ends, and it is what a call's speaking
  /// analytics are anchored to — construct uses need an event id, and a call has
  /// no other event to point at.
  static const call = "pangea.call";

  /// Turning down a call, sent to the room so the caller stops ringing and both
  /// sides can show what happened. Named for MSC4310, which defines exactly this
  /// for MatrixRTC and is implemented in Element Call under the same unstable
  /// prefix — so a Matrix client that speaks it will understand ours.
  /// A call announcing itself so the other side rings. A timeline event
  /// because state changes do not fire push rules — MSC4075, matching what
  /// Element Call sends today.
  static const callNotification = "org.matrix.msc4075.rtc.notification";

  static const callDecline = "org.matrix.msc4310.rtc.decline";

  static const botOptions = "pangea.bot_options";
  static const capacity = "pangea.capacity";

  static const activityPlan = "pangea.activity_plan";
  static const activityRole = "pangea.activity_roles";
  static const activitySummary = "pangea.activity_summary";

  /// Timeline event a client sends into a course space when its seat claim (or
  /// the bot's, on its behalf) fills the last open role of a session listed
  /// there. Coursemates never sync the session room, so this is the sync tick
  /// that re-runs their joinable-session discovery and drops the now-full
  /// session from their course page (#8735). A custom type rather than
  /// m.room.message: it matches no push rule, so it never notifies or badges.
  static const activitySessionFilled = "pangea.activity_session_filled";

  /// Written once by the room admin when they choose "play with bot", marking
  /// the bot as a deliberate activity participant. Its presence is the bot's gate
  /// to claim a role; without it the bot stays idle or moderates silently. Admin-
  /// only and written in one place, so no write-permission risk. See issue #7027.
  static const botParticipant = "pangea.bot_participant";

  static const orchestratorOutput = "pangea.orchestrator_output";
  static const orchestratorAwardedGoals = "pangea.orchestrator_awarded_goals";

  static const report = 'm.report';
  static const textToSpeechRule = "p.rule.text_to_speech";
  static const analyticsInviteRule = "p.rule.analytics_invite";
  static const analyticsInviteContent = "p.analytics_request";

  /// A practice exercise that is related to a message
  static const pangeaActivity = "pangea.activity_res";

  /// Profile information related to a user's analytics
  static const profileAnalytics = "pangea.analytics_profile";

  /// Relates to course plans
  static const coursePlan = "pangea.course_plan";
  // deprecated, no longer used in client, used to filter out of permissions list
  static const courseUser = "p.course_user";
  static const teacherMode = "pangea.teacher_mode";
  static const courseChatList = "pangea.course_chat_list";
  static const courseSettings = "pangea.course_settings";

  static const analyticsSettings = "pangea.analytics_settings";

  static const regenerationRequest = "pangea.regeneration_request";
  static const botNotificationOpened = "p.room.notice.opened";

  static const knockedRooms = 'org.pangea.knocked_rooms';
  static const notificationSettings = 'org.pangea.notification_settings';

  static const accessNoticeShown = 'org.pangea.analytics_access_notice_shown';

  static const firstBotDMMessage = "pangea_first_bot_dm_message";

  static const onboardingSettings = "org.pangea.onboarding_settings";
}

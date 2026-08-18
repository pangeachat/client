//TODO move baseAPI addition to request function

import 'package:fluffychat/pangea/common/config/environment.dart';

/// autodocs
/// https://api.staging.pangea.chat/choreo/docs
/// username: admin
/// password: admin
///
/// https://api.staging.pangea.chat/api/v1/
class PApiUrls {
  static const String _choreoPrefix = "/choreo";
  static const String _subscriptionPrefix = "/subscription";

  static String get _choreoRoute =>
      "${Environment.choreoApi}${PApiUrls._choreoPrefix}";
  static String get _subscriptionRoute =>
      "${Environment.choreoApi}${PApiUrls._subscriptionPrefix}";

  ///  ---------------------- Util --------------------------------------
  static String appVersion = "${PApiUrls._choreoRoute}/version";

  ///   ---------------------- Languages --------------------------------------
  /// CMS REST API endpoint for languages (public, no auth required)
  static String cmsLanguages = "${Environment.cmsApi}/cms/api/languages";

  ///   ---------------------- Analytics dual-write ----------------------------
  /// Teacher-BFF (admin-dash-api) student-authenticated ingest for the
  /// best-effort analytics dual-write. Lives on [Environment.teacherBffApi],
  /// NOT the choreo endpoint. Empty base => the dual-write is skipped.
  static String get analyticsEvents =>
      "${Environment.teacherBffApi}/api/internal/analytics-events";

  ///   ---------------------- Dosage signals ----------------------------------
  /// Teacher-BFF (admin-dash-api) student-authenticated ingest for the
  /// best-effort dosage signals (see [DosageSignalsRepo]). All of them live on
  /// [Environment.teacherBffApi], NOT the choreo endpoint. Empty base => the
  /// signal POST is skipped.
  static String get dosageMessageEvents =>
      "${Environment.teacherBffApi}/api/internal/dosage/message-events";
  static String get dosageEngagementSpans =>
      "${Environment.teacherBffApi}/api/internal/dosage/engagement-spans";
  static String get dosageSessionOutcomes =>
      "${Environment.teacherBffApi}/api/internal/dosage/session-outcomes";

  /// Audio playback signals AND their coverage declarations, in ONE body so the
  /// server can write both in one transaction. A period whose events landed
  /// while its declaration did not would let the server serve an undercount as a
  /// confident total, so the two must never be separable in transit.
  ///
  /// Absent (404) until the server ships this route behind its ingest flag; the
  /// client treats that as undelivered and retries, so the counters withhold
  /// rather than lie.
  static String get dosageAudioSignals =>
      "${Environment.teacherBffApi}/api/internal/dosage/audio-signals";

  ///   ---------------------- Users --------------------------------------
  static String languageDetection =
      "${PApiUrls._choreoRoute}/language_detection";

  static String igcLite = "${PApiUrls._choreoRoute}/grammar_v2";

  static String simpleTranslation =
      "${PApiUrls._choreoRoute}/translation/direct";
  static String tokenize = "${PApiUrls._choreoRoute}/tokenize";

  static String textToSpeech = "${PApiUrls._choreoRoute}/text_to_speech";
  static String speechToText = "${PApiUrls._choreoRoute}/speech_to_text";

  /// Streaming-STT relay WebSocket (`/choreo/speech_to_text/stream`), as the
  /// `wss://`/`ws://` form of the choreo route so `WebSocketChannel.connect`
  /// gets a valid ws scheme. `https` → `wss`, `http` → `ws`; anything else is
  /// returned unchanged.
  static String get speechToTextStream {
    final route = "${PApiUrls._choreoRoute}/speech_to_text/stream";
    if (route.startsWith("https://")) {
      return route.replaceFirst("https://", "wss://");
    }
    if (route.startsWith("http://")) {
      return route.replaceFirst("http://", "ws://");
    }
    return route;
  }

  static String phoneticTranscriptionV2 =
      "${PApiUrls._choreoRoute}/phonetic_transcription_v2";

  static String messagePracticeExerciseGeneration =
      "${PApiUrls._choreoRoute}/practice";

  static String lemmaDictionary = "${PApiUrls._choreoRoute}/lemma_definition";
  static String morphDictionary = "${PApiUrls._choreoRoute}/morph_meaning";

  static String activitySummary = "${PApiUrls._choreoRoute}/activity_summary";

  static String activityFeedback =
      "${PApiUrls._choreoRoute}/activity_plan/feedback";

  /// Single localized read path for a full activity plan, by id.
  /// `GET /choreo/v2/activity/{activity_id}?l1=<viewer_l1>` — translate-on-miss
  /// persists the row (not paywalled). The canonical client read; replaces the
  /// direct CMS query. See activities.instructions.md.
  static String activityById(String activityId) =>
      "${PApiUrls._choreoRoute}/v2/activity/$activityId";

  /// Thin activity map pins within a viewport bbox (world_v2 map search).
  /// Query: min_lat, min_lng, max_lat, max_lng, l2?, cefr_level?, l1?, limit?.
  static String activitiesBbox = "${PApiUrls._choreoRoute}/v2/activities/bbox";

  /// The quest's activities (full canonical plans + LO refs) in one read —
  /// the membership-aware course listing. Query: course_room_id? — when it
  /// names a course the caller is a joined member of, the quest owner's
  /// private activities are included. Replaces the direct CMS activity list
  /// for course scope. See activities.instructions.md § Ownership,
  /// visibility, and removal.
  static String questActivities(String questId) =>
      "${PApiUrls._choreoRoute}/quests/$questId/activities";

  /// Thumbs up/down on an activity (one opinion per user; server upserts).
  /// `POST /choreo/v2/activity/rate` — not paywalled. 403 = self-rating,
  /// 422 = comment rejected by moderation.
  static String activityRate = "${PApiUrls._choreoRoute}/v2/activity/rate";

  static String tokenFeedback = "${PApiUrls._choreoRoute}/token/feedback";
  static String tokenFeedbackV2 = "${PApiUrls._choreoRoute}/token/feedback_v2";

  static String morphFeaturesAndTags = "${PApiUrls._choreoRoute}/morphs";

  static String grammarConstructs =
      "${PApiUrls._choreoRoute}/grammar_constructs";
  static String grammarConstructFeatures =
      "${PApiUrls._choreoRoute}/grammar_constructs/canonical";
  static String grammarConstructMeaning =
      "${PApiUrls._choreoRoute}/grammar_constructs/meaning";

  ///--------------------------- course translations ---------------------------
  static String getLocalizedCourse =
      "${PApiUrls._choreoRoute}/course_plans/localize";
  static String getLocalizedTopic = "${PApiUrls._choreoRoute}/topics/localize";
  static String getLocalizedActivity =
      "${PApiUrls._choreoRoute}/activity_plan/localize";
  static String requestCustomCourse =
      "${PApiUrls._choreoRoute}/courses/request";

  // subscriptions v2
  static String subscriptionProducts = "$_subscriptionRoute/products";
  static String validatePromoCode = "$_subscriptionRoute/validate_promo_code";
  static String subscriptionCheckout = "$_subscriptionRoute/checkout";
  static String subscriptionStatus = "$_subscriptionRoute/status";
  static String subscriptionCancel = "$_subscriptionRoute/cancel";
  static String subscriptionHistory = "$_subscriptionRoute/history";
  static String billingPortal = "$_subscriptionRoute/billing_portal";
  static String freeTrial = "$_subscriptionRoute/free_trial";
}

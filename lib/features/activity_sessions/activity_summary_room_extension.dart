import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_analytics_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_request_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

extension ActivitySummaryRoomExtension on Room {
  ActivitySummaryModel? activitySummary(String langCode) {
    final stateEvent = getState(PangeaEventTypes.activitySummary, langCode);
    if (stateEvent == null) return null;

    try {
      return ActivitySummaryModel.fromJson(stateEvent.content);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"roomID": id, "stateEvent": stateEvent.content},
      );
      return null;
    }
  }

  ActivitySummaryModel? get activitySummaryByL1 {
    final l1 = MatrixState.pangeaController.userController.userL1Code;
    if (l1 == null) return null;
    return activitySummary(l1);
  }

  Future<void> _setActivitySummary(
    ActivitySummaryModel summary,
    String langCode,
  ) async {
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activitySummary,
      langCode,
      summary.toJson(),
    );
  }

  ActivitySummaryRequestModel _constructSummaryRequest(
    List<PangeaMessageEvent> messageEvents,
    String langCode, {
    required ActivityPlanModel activity,
    String? feedback,
  }) {
    final List<ActivitySummaryResultsMessage> messages = [];
    for (final messageEvent in messageEvents) {
      ActivitySummaryResultsMessage activityMessage;
      if (messageEvent.isAudioMessage) {
        // A voice message without a transcript still counts as participation —
        // dropping it silently made voice-heavy sessions look empty to the
        // summary (#7660). The placeholder is a choreographer contract; the
        // prompt counts it as participation without inventing its content.
        final transcript =
            messageEvent.getSpeechToTextLocal()?.transcript.text.trim() ??
            ActivitySessionConstants.sttUnavailablePlaceholder;

        activityMessage = ActivitySummaryResultsMessage(
          userId: messageEvent.senderId,
          sent: transcript,
          written: transcript,
          time: messageEvent.originServerTs,
          tool: [],
        );
      } else {
        activityMessage = ActivitySummaryResultsMessage(
          userId: messageEvent.senderId,
          sent: messageEvent.originalSent?.text ?? messageEvent.body,
          written: messageEvent.originalWrittenContent,
          time: messageEvent.originServerTs,
          tool: [
            if (messageEvent.originalSent?.choreo?.includedIT == true) "it",
            if (messageEvent.originalSent?.choreo?.includedIGC == true) "igc",
          ],
        );
      }

      messages.add(activityMessage);
    }

    final List<ContentFeedbackModel> contentFeedback = [];
    if (feedback != null) {
      final prevSummary = activitySummary(langCode);
      if (prevSummary?.summary != null) {
        contentFeedback.add(
          ContentFeedbackModel(
            feedback: feedback,
            content: prevSummary!.summary!,
          ),
        );
      }
    }

    return ActivitySummaryRequestModel(
      activity: activity,
      activityResults: messages,
      contentFeedback: contentFeedback,
      roleState: activityRoles,
      langCode: langCode,
    );
  }

  ActivitySummaryAnalyticsModel _constrctSummaryAnalyticsModel(
    List<PangeaMessageEvent> messageEvents,
    String langCode,
  ) {
    final ActivitySummaryAnalyticsModel analytics =
        activitySummary(langCode)?.analytics ?? ActivitySummaryAnalyticsModel();
    for (final messageEvent in messageEvents) {
      analytics.addMessageConstructs(messageEvent);
    }
    return analytics;
  }

  Future<void> _startRequestingActivitySummary(String langCode) =>
      _setActivitySummary(
        ActivitySummaryModel(requestedAt: DateTime.now()),
        langCode,
      );

  Future<void> _stopRequestActivitySummaryOnSuccess(
    ActivitySummaryResponseModel resp,
    ActivitySummaryAnalyticsModel? analytics,
    String langCode,
  ) => _setActivitySummary(
    ActivitySummaryModel(summary: resp, analytics: analytics),
    langCode,
  );

  Future<void> _stopRequestingActivitySummaryOnError(
    ActivitySummaryAnalyticsModel? analytics,
    String langCode,
  ) => _setActivitySummary(
    ActivitySummaryModel(errorAt: DateTime.now(), analytics: analytics),
    langCode,
  );

  Future<void> fetchSummaries(String langCode, {String? feedback}) async {
    if (activitySummary(langCode)?.summary != null && feedback == null) return;
    await _startRequestingActivitySummary(langCode);

    final events = await getAllEvents();
    final timeline = this.timeline ?? await getTimeline();
    final messageEvents = getPangeaMessageEvents(
      events,
      timeline,
      msgtypes: [MessageTypes.Text, MessageTypes.Audio],
    );

    // The plan body is canonical in CMS (reference-only room state); resolve it
    // before building the request rather than assuming it is hydrated.
    final activity =
        activityPlan ??
        await ActivityPlanRepo.instance.getPlan(activityId ?? '');
    if (activity == null) {
      await _stopRequestingActivitySummaryOnError(null, langCode);
      return;
    }
    final req = _constructSummaryRequest(
      messageEvents,
      langCode,
      activity: activity,
      feedback: feedback,
    );
    final analytics = _constrctSummaryAnalyticsModel(messageEvents, langCode);

    final result = await ActivitySummaryRepo.get(id, req);
    if (result.isError) {
      if (activitySummary(langCode)?.summary == null) {
        await _stopRequestingActivitySummaryOnError(analytics, langCode);
      }
    } else {
      await _stopRequestActivitySummaryOnSuccess(
        result.result!,
        analytics,
        langCode,
      );
    }

    ActivitySummaryRepo.delete(id, req);
  }

  Future<void> fetchSummariesByL1({String? feedback}) async {
    final l1 = MatrixState.pangeaController.userController.userL1Code;
    if (l1 == null) return;
    return fetchSummaries(l1, feedback: feedback);
  }
}

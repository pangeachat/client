import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_analytics_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// State keys of `pangea.activity_summary`. Each slot has one writer (org doc
/// activity-summary.instructions.md, "Coordination model").
abstract final class ActivitySummaryStateKeys {
  /// The bot's loading marker, error marker, or summary.
  static const canonical = 'canonical';

  /// The room's vocabulary and grammar use, written by the first client that
  /// finds it missing.
  static const analytics = 'analytics';

  /// A learner's retry or feedback, which the bot serves.
  static const request = 'request';

  /// Where clients wrote the summary before the bot made it (the preview
  /// endpoint reports it as `default`).
  static const legacy = '';
  static const legacyPreview = 'default';
}

/// How long the bot keeps serving requests after it writes a summary. It
/// leaves the room after that, so nothing would answer.
const Duration activitySummaryServiceWindow = Duration(hours: 24);

/// What a finished activity shows where its summary goes.
class ActivitySummaryView {
  final ActivitySummaryResponseModel? summary;
  final bool isLoading;

  /// Nothing to show and nothing coming: the error, with a retry when
  /// [canRequest].
  final bool hasFailed;

  /// A regeneration failed; [summary] is the one the learner already had.
  final bool updateFailed;

  /// The bot is still serving this room, so a retry or feedback is answered.
  final bool canRequest;

  /// When [isLoading] ends if nothing lands first. Nothing rebuilds on its
  /// own at that moment, so the owner schedules a recompute.
  final DateTime? loadingDeadline;

  const ActivitySummaryView({
    required this.summary,
    required this.isLoading,
    required this.hasFailed,
    required this.updateFailed,
    required this.canRequest,
    required this.loadingDeadline,
  });

  static const empty = ActivitySummaryView(
    summary: null,
    isLoading: false,
    hasFailed: false,
    updateFailed: false,
    canRequest: false,
    loadingDeadline: null,
  );
}

extension ActivitySummaryRoomExtension on Room {
  /// The bot's `canonical` slot. Any learner can write this event type, so a
  /// write by anyone but the bot is ignored.
  Event? get _canonicalSummaryEvent {
    final event = getState(
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.canonical,
    );
    // An invited room holds stripped state only, with no timestamps.
    if (event is! Event) return null;
    if (event.senderId != BotName.byEnvironment) {
      ErrorHandler.logErrorOnce(
        key: 'activity_summary_foreign_canonical:$id',
        e: 'Canonical activity summary written by a non-bot sender',
        data: {'roomID': id, 'sender': event.senderId},
      );
      return null;
    }
    return event;
  }

  ActivitySummaryModel? _parseSummary(StrippedStateEvent? event) {
    if (event == null) return null;
    try {
      return ActivitySummaryModel.fromJson(event.content);
    } catch (e, s) {
      ErrorHandler.logErrorOnce(
        key: 'activity_summary_parse:$id:${event.stateKey}',
        e: e,
        s: s,
        data: {'roomID': id, 'stateKey': event.stateKey},
      );
      return null;
    }
  }

  /// The bot's summary, else one an older client wrote under the viewer's L1
  /// or the unkeyed slot.
  ActivitySummaryModel? get activitySummary {
    final canonical = _parseSummary(_canonicalSummaryEvent);
    if (canonical != null) return canonical;

    final l1 = MatrixState.pangeaController.userController.userL1Code;
    return _parseSummary(
          l1 == null ? null : getState(PangeaEventTypes.activitySummary, l1),
        ) ??
        _parseSummary(
          getState(
            PangeaEventTypes.activitySummary,
            ActivitySummaryStateKeys.legacy,
          ),
        );
  }

  ActivitySummaryModel? get visibleActivitySummary {
    // account for edge case of activity summary in non-finished activity
    if (!isActivityFinished) return null;
    return activitySummary;
  }

  /// True once a generated summary is on screen. The summary carries the
  /// learner's goals from then on, so the goal header steps aside (#8289).
  bool get hasGeneratedActivitySummary =>
      visibleActivitySummary?.summary != null;

  /// The room's vocabulary and grammar use, from its own slot or, for a
  /// session summarized before that slot existed, from the old summary.
  ActivitySummaryAnalyticsModel? get activitySummaryAnalytics {
    final event = getState(
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.analytics,
    );
    if (event != null) {
      try {
        return ActivitySummaryAnalyticsModel.fromJson(event.content);
      } catch (e, s) {
        ErrorHandler.logErrorOnce(
          key: 'activity_summary_parse:$id:${event.stateKey}',
          e: e,
          s: s,
          data: {'roomID': id, 'stateKey': event.stateKey},
        );
      }
    }
    return activitySummary?.analytics;
  }

  /// Computes the room's analytics from its messages and writes them, when
  /// the activity is finished and no client has yet.
  Future<void> ensureActivitySummaryAnalytics() async {
    if (!isActivityFinished || activitySummaryAnalytics != null) return;
    // A signed-out account has nothing to record (CLIENT-EQW, #9099).
    if (!client.isLogged()) return;

    final events = await getAllEvents();
    final timeline = this.timeline ?? await getTimeline();
    final messageEvents = getPangeaMessageEvents(
      events,
      timeline,
      msgtypes: [MessageTypes.Text, MessageTypes.Audio],
    );
    final analytics = ActivitySummaryAnalyticsModel();
    for (final messageEvent in messageEvents) {
      analytics.addMessageConstructs(messageEvent);
    }
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.analytics,
      analytics.toJson(),
    );
  }

  /// Asks the bot to retry, or to regenerate with [feedback]. The timestamp
  /// keeps a repeat request from matching the current state, which the
  /// homeserver would drop as a no-op.
  Future<void> requestActivitySummary({String? feedback}) async {
    if (!client.isLogged()) return;
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.request,
      {
        'feedback': ?feedback,
        'requested_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  bool get _botIsJoined =>
      getParticipants()
          .firstWhereOrNull((u) => u.id == BotName.byEnvironment)
          ?.membership ==
      Membership.join;

  /// A request the bot has not started serving yet, by the rule the bot uses:
  /// newer than the start of the call behind the canonical slot.
  Event? _pendingSummaryRequest(Event? canonicalEvent) {
    final request = getState(
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.request,
    );
    if (request is! Event) return null;
    final handledUntil =
        _parseSummary(canonicalEvent)?.callStartedTs ??
        canonicalEvent?.originServerTs.millisecondsSinceEpoch;
    if (handledUntil != null &&
        request.originServerTs.millisecondsSinceEpoch <= handledUntil) {
      return null;
    }
    return request;
  }

  /// [waitingSince] is when this client first saw the activity finished with
  /// no summary slot; the bot gets [ActivitySummaryModel.requestTimeout] from
  /// then to write one. Every loading state ends at a deadline, so a bot or
  /// network that never answers ends in the error, not an endless spinner
  /// (#8362).
  ActivitySummaryView activitySummaryView({required DateTime? waitingSince}) {
    if (!isActivityFinished) return ActivitySummaryView.empty;

    final now = DateTime.now();
    final canonicalEvent = _canonicalSummaryEvent;
    final model = activitySummary;

    final pendingRequest = _pendingSummaryRequest(canonicalEvent);
    final loadingDeadline = [
      if (model != null && model.isLoading) model.loadingDeadline,
      pendingRequest?.originServerTs.add(ActivitySummaryModel.requestTimeout),
      if (model == null && waitingSince != null)
        waitingSince.add(ActivitySummaryModel.requestTimeout),
    ].nonNulls.where((deadline) => deadline.isAfter(now)).maxOrNull;
    final isLoading = loadingDeadline != null;

    final summary = isLoading ? null : model?.summary;
    // Once the bot has written its slot, its service window says whether it
    // is still here. Before that, only its membership can, and members load
    // lazily, so it decides nothing else. A summary an older client wrote
    // gets no feedback: the bot has none of its own to regenerate.
    final canRequest = canonicalEvent != null
        ? model?.summary == null ||
              canonicalEvent.originServerTs
                  .add(activitySummaryServiceWindow)
                  .isAfter(now)
        : model?.summary == null && _botIsJoined;

    return ActivitySummaryView(
      summary: summary,
      isLoading: isLoading,
      hasFailed: !isLoading && summary == null,
      updateFailed: summary != null && model!.hasError,
      canRequest: canRequest,
      loadingDeadline: isLoading ? loadingDeadline : null,
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart' show Result;
import 'package:matrix/matrix.dart' hide Result;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_analytics_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_preview_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_analytics_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_request_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityChatController {
  final String userID;
  final Room room;

  /// The chat input's focus node, so opening the activity dropdown can dismiss
  /// the keyboard (restored to parity with main).
  final FocusNode inputFocus;

  ActivityChatController({
    required this.userID,
    required this.room,
    required this.inputFocus,
  }) {
    init();
  }

  bool _disposed = false;
  bool _ensuringSummaryAnalytics = false;

  final ValueNotifier<Set<String>> usedVocab = ValueNotifier({});
  final ValueNotifier<ActivityRoleModel?> highlightedRole = ValueNotifier(null);
  final ValueNotifier<bool> showInstructions = ValueNotifier(false);
  final ValueNotifier<bool> showActivityDropdown = ValueNotifier(false);
  final ValueNotifier<bool> confettiNotifier = ValueNotifier(false);

  /// What the finished activity shows where its summary goes. Recomputed on
  /// every room-state change that feeds it, and when a loading state expires.
  final ValueNotifier<ActivitySummaryView> summaryView = ValueNotifier(
    ActivitySummaryView.empty,
  );

  /// When this client first saw the activity finished with no summary slot.
  DateTime? _summaryWaitingSince;

  Timer? _summaryLoadingTimer;

  /// The translation of the bot's summary into the viewer's L1: which row and
  /// language it is for, and its result once fetched (null while in flight).
  String? _translationKey;
  Result<ActivitySummaryResponseModel>? _translationResult;

  /// A summary slot changed while this controller was up, so the next summary
  /// on screen is a new one to celebrate, not one the learner reopened.
  bool _summaryMayHaveLanded = false;

  late final StreamSubscription _analyticsSubscription;
  late final StreamSubscription _rolesSubscription;
  late final StreamSubscription _summarySubscription;

  void init() {
    _updateUsedVocab();
    _setRolesSubscription();
    _setSummarySubscription();
    _setAnalyticsSubscription();
    _onActivitySummaryInputsChanged();
  }

  Future<void> dispose() async {
    _disposed = true;
    _analyticsSubscription.cancel();
    usedVocab.dispose();
    highlightedRole.dispose();
    showInstructions.dispose();
    showActivityDropdown.dispose();
    confettiNotifier.dispose();
    _summaryLoadingTimer?.cancel();
    summaryView.dispose();
    _rolesSubscription.cancel();
    _summarySubscription.cancel();
    await _onLeaveActivitySession();
  }

  bool get hasSummary => summaryView.value.summary != null;

  void _setRolesSubscription() {
    // A seat finishing, or a learner or the bot leaving, can finish the
    // activity or change who can answer a request.
    _rolesSubscription = room.client.onRoomState.stream
        .where(
          (event) =>
              event.roomId == room.id &&
              {
                PangeaEventTypes.activityRole,
                EventTypes.RoomMember,
              }.contains(event.state.type),
        )
        .listen((_) => _onActivitySummaryInputsChanged());
  }

  void _setSummarySubscription() {
    _summarySubscription = room.client.onRoomState.stream
        .where(
          (event) =>
              event.roomId == room.id &&
              event.state.type == PangeaEventTypes.activitySummary,
        )
        .listen((update) {
          final stateKey = update.state.stateKey;
          if (stateKey != ActivitySummaryStateKeys.analytics &&
              stateKey != ActivitySummaryStateKeys.request) {
            _summaryMayHaveLanded = true;
          }
          _onActivitySummaryInputsChanged();
        });
  }

  void _onActivitySummaryInputsChanged() {
    _refreshSummaryView();
    _ensureSummaryAnalytics();
  }

  void _refreshSummaryView() {
    if (_disposed) return;
    if (room.isActivityFinished && room.activitySummary == null) {
      _summaryWaitingSince ??= DateTime.now();
    }
    final view = _withTranslation(
      room.activitySummaryView(waitingSince: _summaryWaitingSince),
    );
    summaryView.value = view;
    if (_summaryMayHaveLanded && view.summary != null) {
      _summaryMayHaveLanded = false;
      showConfetti();
    }

    _summaryLoadingTimer?.cancel();
    final deadline = view.loadingDeadline;
    if (deadline != null) {
      _summaryLoadingTimer = Timer(
        deadline.difference(DateTime.now()),
        _refreshSummaryView,
      );
    }
  }

  /// [view] as this viewer sees it: the bot's summary translated into their
  /// L1 when it is written in another language. The loading state stays up
  /// while the translation is fetched, and a failed translation leaves the
  /// summary as written.
  ActivitySummaryView _withTranslation(ActivitySummaryView view) {
    final viewerL1 = MatrixState.pangeaController.userController.userL1Code;
    if (viewerL1 == null || !view.needsTranslation(viewerL1)) return view;

    final sourceRequestHash = view.summaryRequestHash;
    if (sourceRequestHash == null) {
      // Choreo returns the row id, and the bot stores it with every summary.
      ErrorHandler.logErrorOnce(
        key: 'activity_summary_no_request_hash',
        e: 'Bot activity summary has no request_hash to translate from',
        data: {'roomID': room.id},
        level: SentryLevel.warning,
      );
      return view;
    }

    final key = '$sourceRequestHash:$viewerL1';
    if (_translationKey != key) {
      _translationKey = key;
      _translationResult = null;
      _fetchTranslation(sourceRequestHash, viewerL1, key);
    }
    final result = _translationResult;
    if (result == null) return view.translatedTo(null);
    return result.isValue ? view.translatedTo(result.asValue!.value) : view;
  }

  Future<void> _fetchTranslation(
    String sourceRequestHash,
    String viewerL1,
    String key,
  ) async {
    // The plan body is canonical in CMS (reference-only room state); resolve
    // it rather than assuming it is hydrated. The repo reports a failed fetch.
    final activity =
        room.activityPlan ??
        await ActivityPlanRepo.instance.getPlan(room.activityId ?? '');
    final result = activity == null
        ? Result<ActivitySummaryResponseModel>.error(
            'No activity plan to translate the summary against',
          )
        : await ActivitySummaryRepo.get(
            room.id,
            ActivitySummaryRequestModel(
              activity: activity,
              sourceRequestHash: sourceRequestHash,
              viewerL1: viewerL1,
            ),
          );
    if (_disposed || _translationKey != key) return;
    _translationResult = result;
    _refreshSummaryView();
  }

  Future<void> _ensureSummaryAnalytics() async {
    if (_ensuringSummaryAnalytics) return;
    _ensuringSummaryAnalytics = true;
    try {
      await room.ensureActivitySummaryAnalytics();
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'roomID': room.id});
    } finally {
      _ensuringSummaryAnalytics = false;
    }
  }

  /// Asks the bot to retry the summary, or to regenerate it with [feedback].
  /// Returns whether the request reached the server; the summary view follows
  /// from room state either way.
  Future<bool> requestSummary({String? feedback}) async {
    try {
      await room.requestActivitySummary(feedback: feedback);
      return true;
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'roomID': room.id});
      return false;
    }
  }

  void _setAnalyticsSubscription() {
    _analyticsSubscription = MatrixState
        .pangeaController
        .matrixState
        .analyticsDataService
        .updateDispatcher
        .constructUpdateStream
        .stream
        .listen((_) => _updateUsedVocab());
  }

  void highlightRole(ActivityRoleModel role) {
    if (!_disposed) {
      highlightedRole.value = role;
    }
  }

  void toggleShowInstructions() {
    if (!_disposed) {
      showInstructions.value = !showInstructions.value;
    }
  }

  void setShowDropdown(bool value) {
    if (!_disposed) {
      if (value) inputFocus.unfocus();
      showActivityDropdown.value = value;
    }
  }

  void toggleShowDropdown() {
    if (!_disposed) {
      showActivityDropdown.value = !showActivityDropdown.value;
    }
  }

  void showConfetti() {
    if (_disposed || confettiNotifier.value) return;
    // The confetti celebrates the summary landing on screen. An unsubscribed
    // learner sees the subscription gate in its place, so a summary arriving
    // in room state — their own fetch or a coursemate's — is nothing to
    // celebrate for them (#8905). Same gate the summary widget renders by.
    final showsSummary = MatrixState
        .pangeaController
        .subscriptionController
        .showSubscriptionGatedContent;
    if (hasSummary && showsSummary) {
      confettiNotifier.value = true;
    }
  }

  bool _updatingUsedVocab = false;
  bool _usedVocabDirty = false;

  Future<void> _updateUsedVocab() async {
    if (room.activityPlan == null || _disposed) return;

    // Coalesce bursts of construct updates: while one timeline scan is in
    // flight, later triggers just mark the result dirty and let the running
    // pass re-run once at the end. Avoids launching concurrent
    // room.getTimeline() calls (documented as unsafe) and redundant full
    // re-scans of the timeline on every analytics tick.
    if (_updatingUsedVocab) {
      _usedVocabDirty = true;
      return;
    }
    _updatingUsedVocab = true;

    try {
      final timeline = await room.getTimeline();
      // requestHistory loads *older* events; new messages arrive via sync and
      // mutate timeline.events in place, so this only needs to run once per
      // burst, not per re-scan.
      await timeline.requestHistory();

      do {
        _usedVocabDirty = false;

        final vocabLemmas = room.activityPlan?.vocabLemmas;
        if (vocabLemmas == null) return;
        final used = <String>{};

        for (final event in timeline.events) {
          if (event.type != EventTypes.Message) continue;
          final uses = PangeaMessageEvent(
            event: event,
            timeline: timeline,
            ownMessage: event.senderId == userID,
          ).constructUses;
          if (uses == null) continue;
          for (final use in uses) {
            if (use.identifier.type == ConstructTypeEnum.vocab) {
              final lemma = use.identifier.lemma.toLowerCase();
              if (vocabLemmas.contains(lemma)) used.add(lemma);
            }
          }
          // Every target word already seen — no need to scan further back.
          if (used.length == vocabLemmas.length) break;
        }

        if (_disposed) return;
        usedVocab.value = used;
      } while (_usedVocabDirty && !_disposed);
    } finally {
      _updatingUsedVocab = false;
    }
  }

  Future<ActivitySummaryAnalyticsModel> getActivityAnalytics() async {
    final cached = ActivitySessionAnalyticsRepo.get(room.id);
    final analytics = cached?.analytics ?? ActivitySummaryAnalyticsModel();
    final activityLang = room.activityPlan?.req.targetLanguage;
    if (activityLang == null) {
      return analytics;
    }

    DateTime? timestamp = room.creationTimestamp;
    if (cached != null) {
      timestamp = cached.lastUseTimestamp;
    }

    List<OneConstructUse> uses = [];
    final analyticsService =
        MatrixState.pangeaController.matrixState.analyticsDataService;

    uses = await analyticsService.getUses(
      activityLang.split('-').first,
      since: timestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
      roomId: room.id,
    );

    if (uses.isEmpty) {
      return analytics;
    }

    analytics.addConstructs(userID, uses);
    await ActivitySessionAnalyticsRepo.set(
      room.id,
      uses.first.metadata.timeStamp,
      analytics,
    );

    return analytics;
  }

  Future<void> submitSummaryFeedback(BuildContext context) async {
    final resp = await showDialog(
      context: context,
      builder: (context) => FeedbackDialog(
        title: L10n.of(context).reportContentIssue,
        onSubmit: (feedback) => Navigator.of(context).pop(feedback),
      ),
    );
    if (resp == null || resp.isEmpty || !context.mounted) {
      return;
    }

    await regenerateSummaryWithFeedback(context, resp);
  }

  /// Asks the bot to regenerate the summary with [feedback], telling the
  /// learner it is under way and then whether the request went through.
  @visibleForTesting
  Future<void> regenerateSummaryWithFeedback(
    BuildContext context,
    String feedback,
  ) async {
    // The summary card swaps to its loading placeholder while the summary
    // regenerates, unmounting [context], so capture what the result needs now.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    final spinnerColor = Theme.of(context).colorScheme.onInverseSurface;

    // Regeneration takes a while, so say it has started. Clearing the current
    // snackbar first keeps this one at the front of the queue, which closing
    // it through its controller requires.
    messenger.hideCurrentSnackBar();
    final processing = messenger.showSnackBarAnnounced(
      SnackBar(
        content: Row(
          spacing: 12.0,
          children: [
            SizedBox.square(
              dimension: 16.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                color: spinnerColor,
              ),
            ),
            Expanded(child: Text(l10n.summaryFeedbackProcessing)),
          ],
        ),
        persist: true,
        showCloseIcon: true,
      ),
      announcement: l10n.summaryFeedbackProcessing,
    );
    var processingShown = true;
    unawaited(processing.closed.then((_) => processingShown = false));

    final ok = await requestSummary(feedback: feedback);
    if (!messenger.mounted) return;
    if (processingShown) processing.close();
    messenger.showSnackBarAnnounced(
      SnackBar(
        content: Text(
          ok ? l10n.summaryFeedbackReceived : l10n.summaryFeedbackFailed,
        ),
        showCloseIcon: true,
      ),
      assertive: !ok,
    );
  }

  Future<void> _onLeaveActivitySession() async {
    final isPreview = await ActivitySessionPreviewRepo.hasPreviewedRoom(
      room.id,
    );
    if (!isPreview) return;

    final hasRole = room.hasPickedRole;
    if (hasRole) {
      await ActivitySessionPreviewRepo.remove(room.id);
      return;
    }

    try {
      await room.leave();
      await ActivitySessionPreviewRepo.remove(room.id);
    } catch (e, s) {
      ErrorHandler.logError(
        e: "Failed to leave previewed activty session",
        s: s,
        data: {'roomId': room.id},
      );
    }
  }
}

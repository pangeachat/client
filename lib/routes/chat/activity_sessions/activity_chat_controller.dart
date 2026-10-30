import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart' show Result;
import 'package:matrix/matrix.dart' hide Result;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
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
import 'package:fluffychat/features/activity_sessions/activity_vocab_matcher.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_visibility.dart';
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
  bool _writingOwnAnalytics = false;

  /// The finish this client last wrote the learner's own analytics for, so a
  /// slot that still reads as older (a device clock running ahead) is not
  /// recomputed on every change.
  DateTime? _ownAnalyticsWrittenFor;

  final ValueNotifier<Set<String>> usedVocab = ValueNotifier({});
  final ValueNotifier<ActivityRoleModel?> highlightedRole = ValueNotifier(null);
  final ValueNotifier<bool> showInstructions = ValueNotifier(false);
  final ValueNotifier<bool> showActivityDropdown = ValueNotifier(false);
  final ValueNotifier<bool> confettiNotifier = ValueNotifier(false);
  final ActivityMediaVisibility mediaVisibility = ActivityMediaVisibility();

  /// What the activity shows where its summary goes. Recomputed on every
  /// room-state change that feeds it, and when a loading state expires.
  final ValueNotifier<ActivitySummaryView> summaryView = ValueNotifier(
    ActivitySummaryView.empty,
  );

  /// The learners whose card this client is waiting for, since it saw them
  /// finish.
  final Map<String, ActivitySummaryWait> _summaryWaits = {};

  /// Who had finished at the last recompute; null before the first, whose
  /// finishes this client did not see happen.
  Set<String>? _finishedLearners;

  Timer? _summaryLoadingTimer;

  /// Translations of cards into the viewer's L1, by source row and language:
  /// null while in flight.
  final Map<String, Result<ActivitySummaryResponseModel>?> _translations = {};

  /// The learner's own card slot changed while this controller was up, so the
  /// next card on screen is a new one to celebrate, not one they reopened.
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
    mediaVisibility.dispose();
    _summaryLoadingTimer?.cancel();
    summaryView.dispose();
    _rolesSubscription.cancel();
    _summarySubscription.cancel();
    await _onLeaveActivitySession();
  }

  /// The card a celebration is for: the learner's own, or for a viewer with
  /// no role, any card.
  bool get hasSummary {
    final view = summaryView.value;
    final own = view.cardFor(userID);
    if (own != null) return own.participant != null;
    return !room.hasPickedRole &&
        view.cards.any((card) => card.participant != null);
  }

  void _setRolesSubscription() {
    // A seat finishing, or a learner or the bot leaving, can bring a card due
    // or change who can answer a request.
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
          if (stateKey != null && _celebrates(stateKey)) {
            _summaryMayHaveLanded = true;
          }
          _onActivitySummaryInputsChanged();
        });
  }

  /// Whether a write to [stateKey] can bring this viewer a card to celebrate:
  /// their own card, a room-wide summary, or for a viewer with no role, any.
  bool _celebrates(String stateKey) {
    final owner = ActivitySummaryStateKeys.cardOwner(stateKey);
    if (owner != null) return owner == userID || !room.hasPickedRole;
    return stateKey != ActivitySummaryStateKeys.analytics &&
        stateKey != ActivitySummaryStateKeys.request &&
        ActivitySummaryStateKeys.analyticsOwner(stateKey) == null;
  }

  void _onActivitySummaryInputsChanged() {
    _updateSummaryWaits();
    _refreshSummaryView();
    _writeOwnAnalytics();
  }

  /// Starts a wait for each learner who finished with no card, or whose card
  /// predates a finish this client saw happen; ends it when they resume.
  void _updateSummaryWaits() {
    if (_disposed) return;
    final finished = room.finishedLearnerIds;
    final before = _finishedLearners;
    final now = DateTime.now();
    for (final userId in finished) {
      if (before != null && !before.contains(userId)) {
        _summaryWaits[userId] = ActivitySummaryWait(
          since: now,
          supersededEventId: room.activitySummaryCardBefore(userId),
        );
      } else if (!room.hasActivitySummarySlot(userId)) {
        _summaryWaits.putIfAbsent(
          userId,
          () => ActivitySummaryWait(since: now),
        );
      }
    }
    _summaryWaits.removeWhere((userId, _) => !finished.contains(userId));
    _finishedLearners = finished;
  }

  void _refreshSummaryView() {
    if (_disposed) return;
    final view = _withTranslations(
      room.activitySummaryView(waits: _summaryWaits),
    );
    summaryView.value = view;
    final own = view.cardFor(userID);
    if (_summaryMayHaveLanded && hasSummary) {
      _summaryMayHaveLanded = false;
      // A failed regeneration keeps the old card on screen; nothing landed.
      if (own?.updateFailed != true) showConfetti();
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

  /// [view] as this viewer sees it: each card translated into their L1 from
  /// its own stored row when it is written in another language. A card stays
  /// loading while its translation is fetched, and a failed translation
  /// leaves it as written.
  ActivitySummaryView _withTranslations(ActivitySummaryView view) {
    final viewerL1 = MatrixState.pangeaController.userController.userL1Code;
    if (viewerL1 == null) return view;

    final cards = [
      for (final card in view.cards)
        if (!card.needsTranslation(viewerL1))
          card
        else
          switch (_translation(card.requestHash, viewerL1)) {
            _NoTranslation() => card,
            _TranslationPending() => card.translatedTo(null),
            _Translated(:final summary) => card.translatedTo(
              summary.userSummary(card.userId) ?? card.participant,
            ),
          },
    ];

    var groupSummary = view.groupSummary;
    final groupLangCode = view.groupLangCode;
    if (groupSummary != null &&
        groupLangCode != null &&
        !PLanguageStore.sameWrittenLanguage(groupLangCode, viewerL1)) {
      switch (_translation(view.groupRequestHash, viewerL1)) {
        case _NoTranslation():
          break;
        case _TranslationPending():
          groupSummary = null;
        case _Translated(:final summary):
          groupSummary = summary.summary.isNotEmpty
              ? summary.summary
              : groupSummary;
      }
    }

    return ActivitySummaryView(
      cards: cards,
      groupSummary: groupSummary,
      groupLangCode: groupLangCode,
      groupRequestHash: view.groupRequestHash,
    );
  }

  /// The translation of the stored row [sourceRequestHash] into [viewerL1],
  /// starting the fetch the first time it is asked for.
  _TranslationState _translation(String? sourceRequestHash, String viewerL1) {
    if (sourceRequestHash == null) {
      // Choreo returns the row id, and the bot stores it with every card.
      ErrorHandler.logErrorOnce(
        key: 'activity_summary_no_request_hash',
        e: 'Bot activity summary has no request_hash to translate from',
        data: {'roomID': room.id},
        level: SentryLevel.warning,
      );
      return const _NoTranslation();
    }

    final key = '$sourceRequestHash:$viewerL1';
    if (!_translations.containsKey(key)) {
      _translations[key] = null;
      _fetchTranslation(sourceRequestHash, viewerL1, key);
    }
    final result = _translations[key];
    if (result == null) return const _TranslationPending();
    return result.isValue
        ? _Translated(result.asValue!.value)
        : const _NoTranslation();
  }

  Future<void> _fetchTranslation(
    String sourceRequestHash,
    String viewerL1,
    String key,
  ) async {
    // The plan body is canonical in CMS (reference-only room state); resolve
    // it rather than assuming it is hydrated. The repo reports a failed fetch,
    // but a malformed plan throws while mapping, and nothing awaits this call,
    // so the throw would leave the viewer on the loading state.
    ActivityPlanModel? activity;
    Object? planError;
    try {
      activity =
          room.activityPlan ??
          await ActivityPlanRepo.instance.getPlan(room.activityId ?? '');
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'roomID': room.id});
      planError = e;
    }
    final result = activity == null
        ? Result<ActivitySummaryResponseModel>.error(
            planError ?? 'No activity plan to translate the summary against',
          )
        : await ActivitySummaryRepo.get(
            room.id,
            ActivitySummaryRequestModel(
              activity: activity,
              sourceRequestHash: sourceRequestHash,
              viewerL1: viewerL1,
            ),
          );
    if (_disposed) return;
    _translations[key] = result;
    _refreshSummaryView();
  }

  /// Writes the learner's own vocabulary and grammar use when they finish,
  /// and again when they end after resuming.
  Future<void> _writeOwnAnalytics() async {
    if (_writingOwnAnalytics || !room.needsOwnActivityAnalytics) return;
    final finishedAt = room.ownRoleState?.finishedAt;
    if (finishedAt == null || finishedAt == _ownAnalyticsWrittenFor) return;
    _writingOwnAnalytics = true;
    try {
      await room.writeOwnActivityAnalytics();
      _ownAnalyticsWrittenFor = finishedAt;
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'roomID': room.id});
    } finally {
      _writingOwnAnalytics = false;
    }
  }

  /// Asks the bot to retry [userId]'s card, or to regenerate it with
  /// [feedback]. Returns whether the request reached the server; the card
  /// follows from room state either way.
  Future<bool> requestSummary({
    required String userId,
    String? feedback,
  }) async {
    try {
      await room.requestActivitySummary(userId: userId, feedback: feedback);
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
          final tokens = PangeaMessageEvent(
            event: event,
            timeline: timeline,
            ownMessage: event.senderId == userID,
          ).sentTokens;
          if (tokens == null) continue;
          used.addAll(ActivityVocabMatcher(tokens, vocabLemmas).matchedEntries);
          // Every target entry already seen — no need to scan further back.
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

  /// Asks the learner what is wrong with [userId]'s card, then has the bot
  /// regenerate it.
  Future<void> submitSummaryFeedback(
    BuildContext context, {
    required String userId,
  }) async {
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

    await regenerateSummaryWithFeedback(
      context,
      userId: userId,
      feedback: resp,
    );
  }

  /// Asks the bot to regenerate [userId]'s card with [feedback], telling the
  /// learner it is under way and then whether the request went through.
  @visibleForTesting
  Future<void> regenerateSummaryWithFeedback(
    BuildContext context, {
    required String userId,
    required String feedback,
  }) async {
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

    final ok = await requestSummary(userId: userId, feedback: feedback);
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

/// Where a card's translation into the viewer's L1 stands.
sealed class _TranslationState {
  const _TranslationState();
}

/// None to wait for: the card shows as written.
class _NoTranslation extends _TranslationState {
  const _NoTranslation();
}

class _TranslationPending extends _TranslationState {
  const _TranslationPending();
}

class _Translated extends _TranslationState {
  final ActivitySummaryResponseModel summary;

  const _Translated(this.summary);
}

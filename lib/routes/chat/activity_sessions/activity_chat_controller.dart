import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_analytics_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_preview_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_analytics_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
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
  bool _loadingSummary = false;

  final ScrollController carouselController = ScrollController();
  final ValueNotifier<Set<String>> usedVocab = ValueNotifier({});
  final ValueNotifier<ActivityRoleModel?> highlightedRole = ValueNotifier(null);
  final ValueNotifier<bool> showInstructions = ValueNotifier(false);
  final ValueNotifier<bool> showActivityDropdown = ValueNotifier(false);
  final ValueNotifier<bool> confettiNotifier = ValueNotifier(false);

  late final StreamSubscription _analyticsSubscription;
  late final StreamSubscription _rolesSubscription;
  late final StreamSubscription _summarySubscription;

  void init() {
    _updateUsedVocab();
    _setRolesSubscription();
    _setSummarySubscription();
    _setAnalyticsSubscription();

    if (room.isActivityFinished && _summary == null) {
      _loadActivitySummary();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    carouselController.dispose();
    _analyticsSubscription.cancel();
    usedVocab.dispose();
    highlightedRole.dispose();
    showInstructions.dispose();
    showActivityDropdown.dispose();
    confettiNotifier.dispose();
    _rolesSubscription.cancel();
    _summarySubscription.cancel();
    await _onLeaveActivitySession();
  }

  ActivitySummaryModel? get _summaryEvent => room.activitySummaryByL1;
  ActivitySummaryResponseModel? get _summary => _summaryEvent?.summary;

  bool get hasSummary => _summary != null;

  void _setRolesSubscription() {
    _rolesSubscription = room.client.onRoomState.stream
        .where(
          (event) =>
              event.roomId == room.id &&
              event.state.type == PangeaEventTypes.activityRole,
        )
        .listen((e) {
          if (room.isActivityFinished) {
            _loadActivitySummary();
          }
        });
  }

  void _setSummarySubscription() {
    _summarySubscription = room.client.onRoomState.stream
        .where(
          (event) =>
              event.roomId == room.id &&
              event.state.type == PangeaEventTypes.activitySummary,
        )
        .listen((e) => showConfetti());
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
    if (hasSummary) {
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

  Future<void> _loadActivitySummary() async {
    if (_loadingSummary) return;
    _loadingSummary = true;

    try {
      if (_summary != null) return;

      // The summary state event is null
      if (_summaryEvent == null) {
        await room.fetchSummariesByL1();
        return;
      }

      // The summary state event is waiting (<= 10 seconds since request)
      // Wait for 10 seconds (or time remaining until not waiting). If summary still not there, run request.
      if (_summaryEvent!.isLoading) {
        final remainingTime = DateTime.now()
            .difference(_summaryEvent!.requestedAt!)
            .inSeconds;

        await Future.delayed(
          Duration(seconds: remainingTime < 10 ? 10 - remainingTime : 0),
          () async {
            if (_summary == null) await room.fetchSummariesByL1();
          },
        );
        return;
      }

      if (_summaryEvent!.errorAt == null) {
        await room.fetchSummariesByL1();
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
    } finally {
      _loadingSummary = false;
    }
  }

  Future<void> submitSummaryFeedback(BuildContext context) async {
    final resp = await showDialog(
      context: context,
      builder: (context) => FeedbackDialog(
        title: L10n.of(context).reportContentIssue,
        onSubmit: (feedback) => Navigator.of(context).pop(feedback),
      ),
    );
    if (resp == null || resp.isEmpty) {
      return;
    }

    await room.fetchSummariesByL1(feedback: resp);
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

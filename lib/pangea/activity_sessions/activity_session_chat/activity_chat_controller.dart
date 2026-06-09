import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_analytics_repo.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_preview/activity_session_preview_repo.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_analytics_model.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_model.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_response_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityChatController {
  final String userID;
  final Room room;

  ActivityChatController({required this.userID, required this.room}) {
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
  late final StreamSubscription _messageSubscription;

  void init() {
    _updateUsedVocab();
    _setRolesSubscription();
    _setSummarySubscription();
    _setAnalyticsSubscription();
    _setMessageSubscription();

    if (room.isActivityFinished && _summary == null) {
      _loadActivitySummary();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    carouselController.dispose();
    _analyticsSubscription.cancel();
    _messageSubscription.cancel();
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

  void _setMessageSubscription() {
    _messageSubscription = room.client.onSync.stream
        .where((sync) => sync.rooms?.join?.containsKey(room.id) == true)
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

  void _updateUsedVocab() {
    final vocab = room.activityPlan?.vocab;
    if (vocab == null || _disposed) return;

    final vocabLemmas = vocab.map((v) => v.lemma.toLowerCase()).toSet();
    final used = <String>{};

    final timeline = room.timeline;
    if (timeline != null) {
      for (final event in timeline.events) {
        if (event.type != EventTypes.Message) continue;
        final uses = PangeaMessageEvent(
          event: event,
          timeline: timeline,
          ownMessage: event.senderId == userID,
        ).originalSent?.vocabAndMorphUses;
        if (uses == null) continue;
        for (final use in uses) {
          if (use.identifier.type == ConstructTypeEnum.vocab) {
            final lemma = use.identifier.lemma.toLowerCase();
            if (vocabLemmas.contains(lemma)) used.add(lemma);
          }
        }
      }
    }

    usedVocab.value = used;
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

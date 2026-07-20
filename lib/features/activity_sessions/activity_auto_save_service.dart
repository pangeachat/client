import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// Whether a session is due for an automatic save: the session ended, this
/// user finished their own role, and they haven't saved it yet. A user who
/// left without finishing never saves (their stars never bank — the incentive
/// to finish).
@visibleForTesting
bool activityAutoSaveGate({
  required bool isActivityFinished,
  required bool hasCompletedRole,
  required bool hasArchivedActivity,
}) => isActivityFinished && hasCompletedRole && !hasArchivedActivity;

/// Saves completed activity sessions automatically — records the session to
/// the learner's analytics room and archives their role — so a session that
/// completes while the learner is elsewhere still saves on the next sync.
/// See activities.instructions.md → "Completion saves itself".
class ActivityAutoSaveService {
  final Client client;
  final AnalyticsDataService analyticsService;

  ActivityAutoSaveService({
    required this.client,
    required this.analyticsService,
  });

  StreamSubscription? _roleStateSub;
  final Set<String> _saving = {};
  bool _disposed = false;

  Future<void> start() async {
    if (!client.isLogged()) {
      await client.onLoginStateChanged.stream.firstWhere(
        (state) => state == LoginState.loggedIn,
      );
    }
    if (client.prevBatch == null) {
      await client.onSync.stream.first;
    }
    if (_disposed) return;

    _roleStateSub = client.onRoomState.stream
        .where((event) => event.state.type == PangeaEventTypes.activityRole)
        .listen((event) => _maybeSave(client.getRoomById(event.roomId)));

    // Reference plans hydrate asynchronously; a room skipped because its plan
    // hadn't resolved yet is retried when the repo notifies.
    ActivityPlanRepo.instance.addListener(_sweep);
    _sweep();
  }

  void dispose() {
    _disposed = true;
    _roleStateSub?.cancel();
    ActivityPlanRepo.instance.removeListener(_sweep);
  }

  void _sweep() {
    for (final room in client.rooms) {
      _maybeSave(room);
    }
  }

  Future<void> _maybeSave(Room? room) async {
    if (_disposed || room == null || !room.isActivitySession) return;
    if (!activityAutoSaveGate(
      isActivityFinished: room.isActivityFinished,
      hasCompletedRole: room.hasCompletedRole,
      hasArchivedActivity: room.hasArchivedActivity,
    )) {
      return;
    }

    // Reading the plan triggers hydration for reference rooms; a null here is
    // retried via the repo listener. A room with no resolvable plan at all
    // can't determine its target language and is skipped.
    final plan = room.activityPlan;
    if (plan == null) return;

    final lang = PLanguageStore.byLangCode(
      plan.req.targetLanguage.split("-").first,
    );
    if (lang == null) return;

    if (!_saving.add(room.id)) return;
    try {
      // Analytics room first: if this write fails, archived_at stays unset and
      // the save retries on the next role-state event or sweep.
      await analyticsService.updateService.sendActivityAnalytics(room.id, lang);
      await room.archiveActivity();

      GoogleAnalytics.completeActivity(
        plan.activityId,
        room.id,
        versionPinHonored: !plan.usedFallbackVersion,
        fallbackCause: plan.fallbackCause,
      );
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'roomId': room.id});
    } finally {
      _saving.remove(room.id);
    }
  }
}

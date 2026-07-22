import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/dosage/dosage_session_outcome.dart';
import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
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

  /// Resolves an activity's LO reference ids (see [defaultLoRefsResolver]);
  /// injectable so the outcome attribution is testable without a live CMS.
  final Future<List<String>> Function(String activityId) _loRefsResolver;

  ActivityAutoSaveService({
    required this.client,
    required this.analyticsService,
    Future<List<String>> Function(String activityId)? loRefsResolver,
  }) : _loRefsResolver = loRefsResolver ?? defaultLoRefsResolver;

  StreamSubscription? _roleStateSub;
  final Set<String> _saving = {};

  /// Session rooms this run has already SAVED (analytics + archive). The gate
  /// (`!hasArchivedActivity`) re-opens until the archive write syncs back, so a
  /// pre-sync sweep would otherwise re-archive and stamp a NEWER `archived_at`,
  /// leaving the already-emitted outcome's timestamp stale. Once saved, the
  /// first archive is authoritative and the room is never saved again.
  final Set<String> _saved = {};

  /// Session rooms whose dosage outcome has already been emitted this app run.
  /// The auto-save gate can re-open before the archive write syncs back, so a
  /// second racing pass would otherwise emit the outcome again — this holds it
  /// to exactly once per session room.
  final Set<String> _emittedOutcomes = {};
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

    // Already saved this run: the first archive is authoritative. The gate above
    // stays open until the archive syncs back, so without this a pre-sync sweep
    // would re-archive with a newer timestamp.
    if (!shouldSave(room.id, _saved)) return;

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
      // archiveActivity returns the canonical archived-at it persisted, so the
      // outcome below uses it directly instead of re-reading room state the
      // archive write may not have synced back yet — a race that would skip the
      // emit permanently once the gate closes on the archived role.
      final archivedAt = await room.archiveActivity();

      // Best-effort dosage session outcome at the archive moment (stars bank
      // here). Fire-and-forget; never blocks or fails the save.
      _emitDosageSessionOutcome(room, archivedAt);

      // Saved successfully: mark authoritative so a pre-sync sweep can't
      // re-archive with a newer timestamp. On failure it stays unmarked and
      // retries on the next role-state event or sweep.
      _saved.add(room.id);

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

  /// Whether a session room still needs saving: false once it has been saved
  /// this run (the first archive is authoritative). The gate that keeps a
  /// pre-sync sweep from re-archiving with a newer timestamp.
  @visibleForTesting
  static bool shouldSave(String roomId, Set<String> saved) =>
      !saved.contains(roomId);

  /// Fire-and-forget the best-effort dosage session-outcome signal at the
  /// archive moment. Every field is a client-side HINT the server re-verifies
  /// against the room's bot-authored state; stars are the learner's own
  /// completed goals (one star each), keyed by goal slug with an id fallback.
  ///
  /// [archivedAt] is the canonical marker archiveActivity persisted (never a
  /// re-read of racy room state); a null means the archive did not happen, so
  /// there is nothing to emit.
  void _emitDosageSessionOutcome(Room room, DateTime? archivedAt) {
    // Guard + dedupe synchronously BEFORE the async LO-ref read so a racing
    // second pass can't start a second resolve/post. Nothing to attribute (no
    // activity id / no archived-at) doesn't burn the dedupe slot.
    if (room.activityId == null || archivedAt == null) return;
    if (!shouldEmitOutcome(room.id, _emittedOutcomes)) return;

    unawaited(
      () async {
        final outcome = await resolveSessionOutcome(
          room: room,
          archivedAt: archivedAt,
          loRefsResolver: _loRefsResolver,
        );
        if (outcome == null) return;
        await DosageSignalsRepo.postSessionOutcomes(
          outcomes: [outcome],
          accessToken: client.accessToken,
        );
      }().catchError((_) {}),
    );
  }

  /// Resolves the dosage session-outcome for [room] at [archivedAt], or null
  /// when it cannot be attributed. Attribution is data-minimized: the pinned
  /// course-space id ([Room.pinnedSourceCourseId], the SPECIFIC launching course
  /// — not an arbitrary course-plan parent), and LO REFERENCE IDS from
  /// [loRefsResolver] — never the free-form learning-objective display text,
  /// which is persisted server-side and can carry authored content/PII.
  ///
  /// Static + injectable resolver so the attribution is unit-testable without a
  /// live CMS.
  @visibleForTesting
  static Future<DosageSessionOutcome?> resolveSessionOutcome({
    required Room room,
    required DateTime? archivedAt,
    required Future<List<String>> Function(String activityId) loRefsResolver,
  }) async {
    final activityId = room.activityId;
    if (activityId == null || archivedAt == null) return null;

    final loRefs = await loRefsResolver(activityId);

    final starsByGoalSlug = <String, int>{
      for (final goal in room.ownCompletedGoals) (goal.goalSlug ?? goal.id): 1,
    };

    return buildSessionOutcome(
      sessionRoomId: room.id,
      activityId: activityId,
      archivedAt: archivedAt,
      sourceCourseId: room.pinnedSourceCourseId,
      loRefs: loRefs,
      starsByGoalSlug: starsByGoalSlug,
    );
  }

  /// An activity's LO reference ids (the CMS `learningObjectiveRefs`), the
  /// PII-safe attribution for `lo_refs`. Best-effort: an empty list on any
  /// failure — the server re-derives LO attribution regardless.
  @visibleForTesting
  static Future<List<String>> defaultLoRefsResolver(String activityId) async {
    try {
      final result = await QuestRepo.activityLearningObjectiveRefs(activityId);
      return result.asValue?.value ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Whether the session outcome for [roomId] should still be emitted: true the
  /// first time, false after (deduped into [alreadyEmitted]). The exactly-once
  /// gate that keeps a re-opened auto-save pass from double-emitting.
  @visibleForTesting
  static bool shouldEmitOutcome(String roomId, Set<String> alreadyEmitted) =>
      alreadyEmitted.add(roomId);

  /// Builds the dosage session-outcome, or null when it cannot be attributed:
  /// no activity id, or no archived-at (the archive did not happen). Pure so the
  /// canonical-timestamp + attribution wiring is unit-testable without a Matrix
  /// room; `completed_at` is exactly the passed [archivedAt].
  @visibleForTesting
  static DosageSessionOutcome? buildSessionOutcome({
    required String sessionRoomId,
    required String? activityId,
    required DateTime? archivedAt,
    required String? sourceCourseId,
    required List<String> loRefs,
    required Map<String, int> starsByGoalSlug,
  }) {
    if (activityId == null || archivedAt == null) return null;
    return DosageSessionOutcome(
      sessionRoomId: sessionRoomId,
      activityId: activityId,
      sourceCourseId: sourceCourseId,
      loRefs: loRefs,
      starsByGoalSlug: starsByGoalSlug,
      completedAt: archivedAt,
    );
  }
}

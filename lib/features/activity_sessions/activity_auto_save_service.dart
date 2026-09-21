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
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_client_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';

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

/// Whether the account this service belongs to may publish its star total now.
///
/// Only while it is the ACTIVE account. The services are per-account and all
/// run at once, but the user controller they publish through is a single global
/// that resolves the active account — so a background account would file its
/// own count on the active account's profile, and a published total is never
/// lowered, so nothing would ever correct it.
@visibleForTesting
bool activeAccountPublishesStars({
  required String? serviceUserId,
  required String? activeUserId,
}) => serviceUserId != null && serviceUserId == activeUserId;

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

  /// DURABLE idempotency (across process restarts) is NOT in-memory state — it
  /// is the SERVER-AUTHORITATIVE `archived_at` in the role state: [start] waits
  /// for the first `/sync` before sweeping, so a restart sees the archived role,
  /// `hasArchivedActivity` is true, the gate (`!hasArchivedActivity`) is closed,
  /// and the session is never re-saved or re-emitted.
  ///
  /// The archived-at this run persisted per session room. An archive is NOT
  /// final once written: every role lives in one shared `pangea.activity_roles`
  /// event, so a co-player archiving from a stale read overwrites the whole map
  /// and drops this user's `archived_at` — the session pops back into the chat
  /// list and its stars unbank until the next app start (#8258). The role-state
  /// listener sees that overwrite and the gate re-opens, so the repair is simply
  /// to archive again — replaying the REMEMBERED instant, so the repaired room
  /// state still matches the dosage outcome already emitted against it.
  final Map<String, DateTime> _archivedAt = {};

  /// Session rooms whose dosage outcome has already been emitted this run (the
  /// intra-run outcome guard; a restart can't double-emit because the synced
  /// `archived_at` closes the gate before the sweep runs).
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
        .listen((event) {
          _maybeSave(client.getRoomById(event.roomId));
          // Stars bank when the role archives, so the published total is
          // recounted on the same signal that banks them.
          _publishStarTotal();
        });

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
    _publishStarTotal();
  }

  /// Publishes the learner's banked star total for the language they are
  /// studying, so classmates can see it on a participant card.
  ///
  /// Runs from the sweep, which happens after the first sync AND every time a
  /// reference plan hydrates — the sessions counted here are matched to a
  /// language by their plan, so a total counted before those plans land is too
  /// low and the recount is what corrects it. Nothing awaits this: the publish
  /// only ever raises the number, so a run that counted an incomplete set is
  /// ignored rather than believed. See profile.instructions.md.
  void _publishStarTotal() {
    // `initState` runs `initMatrix()` — which starts this service — BEFORE it
    // assigns `MatrixState.pangeaController`, and a restored, already-synced
    // session reaches [start]'s sweep without ever awaiting, so the first
    // publish can land while that `late` field is still unset and reading it
    // throws (#8712). Skipping is free: the next sweep republishes, and the
    // total only ever rises, so a skipped run costs nothing a later one does
    // not correct.
    if (!MatrixState.isPangeaControllerInitialized) return;

    final userController = MatrixState.pangeaController.userController;

    // A background account publishes on its next sweep after it is switched to
    // — see [activeAccountPublishesStars] for why it must not publish now.
    if (!activeAccountPublishesStars(
      serviceUserId: client.userID,
      activeUserId: userController.client.userID,
    )) {
      return;
    }

    final l2 = userController.userL2;
    if (l2 == null) return;

    userController
        .updateAnalyticsStars(
          languageCode: l2.langCodeShort,
          stars: client.totalStarsEarned(l2),
        )
        .catchError(
          (Object e, StackTrace s) =>
              ErrorHandler.logError(e: e, s: s, data: {'lang': l2.langCode}),
        );
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
    // A repair pass re-persists an archive a co-player's write dropped; the
    // session completed once, so it must not be COUNTED again.
    final isRepair = _archivedAt.containsKey(room.id);
    try {
      // Analytics room first: if this write fails, archived_at stays unset and
      // the save retries on the next role-state event or sweep.
      await analyticsService.updateService.sendActivityAnalytics(room.id, lang);
      // archiveActivity returns the canonical archived-at it persisted, so the
      // outcome below uses it directly instead of re-reading room state the
      // archive write may not have synced back yet — a race that would skip the
      // emit permanently once the gate closes on the archived role. Replaying
      // `_archivedAt` keeps a repair write (see the field doc) on the instant
      // this run first banked, so a second pass is idempotent in content.
      final archivedAt = await room.archiveActivity(at: _archivedAt[room.id]);

      // Remember the canonical instant FIRST — BEFORE any best-effort telemetry
      // — so a throw from the emit below can never lose it. On archive failure
      // this line isn't reached and it retries on the next role-state event or
      // sweep.
      if (archivedAt != null) _archivedAt[room.id] = archivedAt;

      // Best-effort dosage session outcome at the archive moment (stars bank
      // here). Fire-and-forget + fully guarded; never blocks or fails the save.
      _emitDosageSessionOutcome(room, archivedAt);

      if (!isRepair) {
        GoogleAnalytics.completeActivity(
          plan.activityId,
          room.id,
          versionPinHonored: !plan.usedFallbackVersion,
          fallbackCause: plan.fallbackCause,
        );
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'roomId': room.id});
    } finally {
      _saving.remove(room.id);
    }
  }

  /// Fire-and-forget the best-effort dosage session-outcome signal at the
  /// archive moment. Every field is a client-side HINT the server re-verifies
  /// against the room's bot-authored state; stars are the learner's own
  /// completed goals (one star each), keyed by goal slug with an id fallback.
  ///
  /// [archivedAt] is the canonical marker archiveActivity persisted (never a
  /// re-read of racy room state); a null means the archive did not happen, so
  /// there is nothing to emit.
  void _emitDosageSessionOutcome(Room room, DateTime? archivedAt) {
    // WHOLE body guarded: this is best-effort telemetry invoked from the save
    // path AFTER the archive is marked, so even its synchronous setup (room
    // field reads, dedupe) must never throw into the save flow.
    try {
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
    } catch (e, s) {
      // Best-effort telemetry — never disturb the save that already committed.
      ErrorHandler.logError(e: e, s: s, data: {'roomId': room.id});
    }
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

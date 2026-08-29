import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_auto_save_service.dart';
import 'package:fluffychat/features/dosage/dosage_session_outcome.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_client_extension.dart';

/// The gate ActivityAutoSaveService uses to decide whether a session is due
/// for its automatic save (pangeachat/client#7648): the session ended, the
/// user finished their own role, and it isn't saved yet. Saving is what banks
/// the session's stars into the profile total, so a user who left without
/// finishing must never pass this gate.
void main() {
  group('activityAutoSaveGate', () {
    test('completed session with own role finished and not yet saved '
        'is due for save', () {
      expect(
        activityAutoSaveGate(
          isActivityFinished: true,
          hasCompletedRole: true,
          hasArchivedActivity: false,
        ),
        isTrue,
      );
    });

    test('already-saved session never re-saves', () {
      expect(
        activityAutoSaveGate(
          isActivityFinished: true,
          hasCompletedRole: true,
          hasArchivedActivity: true,
        ),
        isFalse,
      );
    });

    // NOTE: durable cross-restart idempotency is NOT a property of this pure
    // gate (a restart with empty in-memory sets still closes the gate purely
    // because the server-synced archived_at makes hasArchivedActivity true,
    // which is the already-saved case above). It is exercised where it actually
    // lives — the empty-set first pass in the shouldEmitOutcome group below —
    // so no vacuous restart-flavoured duplicate of the already-saved assertion
    // is kept here.
    //
    // The same first case also covers the #8258 repair: when a co-player's
    // stale-read write drops this user's archived_at, hasArchivedActivity goes
    // false again and the gate re-opens, which is what lets the service
    // re-archive. The replay of the ORIGINAL instant is asserted in
    // activity_archive_activity_test.dart.

    test('session still in progress does not save', () {
      expect(
        activityAutoSaveGate(
          isActivityFinished: false,
          hasCompletedRole: true,
          hasArchivedActivity: false,
        ),
        isFalse,
      );
    });

    test('session ended but own role never finished (user abandoned) '
        'does not save — abandoned stars never bank', () {
      expect(
        activityAutoSaveGate(
          isActivityFinished: true,
          hasCompletedRole: false,
          hasArchivedActivity: false,
        ),
        isFalse,
      );
    });
  });

  group('totalBankedStars', () {
    test('unsaved sessions contribute nothing to the profile total', () {
      expect(
        totalBankedStars([
          (activityId: 'a', earned: 3, saved: false),
          (activityId: 'b', earned: 2, saved: false),
        ]),
        0,
      );
    });

    test('saved sessions bank their stars', () {
      expect(
        totalBankedStars([
          (activityId: 'a', earned: 3, saved: true),
          (activityId: 'b', earned: 2, saved: true),
        ]),
        5,
      );
    });

    test('replays of the same activity dedupe to the best saved run', () {
      expect(
        totalBankedStars([
          (activityId: 'a', earned: 1, saved: true),
          (activityId: 'a', earned: 3, saved: true),
        ]),
        3,
      );
    });

    test('an unsaved run with more stars than the saved run of the same '
        'activity does not raise the total', () {
      expect(
        totalBankedStars([
          (activityId: 'a', earned: 2, saved: true),
          (activityId: 'a', earned: 4, saved: false),
        ]),
        2,
      );
    });
  });

  group('shouldEmitOutcome (dosage outcome exactly-once)', () {
    test('emits the first time, never again for the same room', () {
      final emitted = <String>{};
      expect(
        ActivityAutoSaveService.shouldEmitOutcome('!s:x', emitted),
        isTrue,
      );
      expect(
        ActivityAutoSaveService.shouldEmitOutcome('!s:x', emitted),
        isFalse,
        reason:
            'the auto-save gate re-opens before the archive syncs back; a '
            'racing second pass must not double-emit the outcome',
      );
    });

    test('tracks each session room independently', () {
      final emitted = <String>{};
      expect(
        ActivityAutoSaveService.shouldEmitOutcome('!a:x', emitted),
        isTrue,
      );
      expect(
        ActivityAutoSaveService.shouldEmitOutcome('!b:x', emitted),
        isTrue,
      );
    });
  });

  group('buildSessionOutcome (canonical archived-at + attribution)', () {
    final archivedAt = DateTime.utc(2026, 1, 1, 12, 30);

    DosageSessionOutcome? build({
      String? activityId = 'act-1',
      DateTime? archived,
      String? sourceCourseId = '!course:x',
      List<String> loRefs = const ['lo-1'],
    }) => ActivityAutoSaveService.buildSessionOutcome(
      sessionRoomId: '!s:x',
      activityId: activityId,
      archivedAt: archived ?? archivedAt,
      sourceCourseId: sourceCourseId,
      loRefs: loRefs,
      starsByGoalSlug: const {'greet': 1},
    );

    test('completed_at is exactly the passed canonical archived-at', () {
      final outcome = build();
      expect(outcome, isNotNull);
      expect(outcome!.completedAt, archivedAt);
      expect(outcome.activityId, 'act-1');
      expect(outcome.sourceCourseId, '!course:x');
      expect(outcome.loRefs, ['lo-1']);
      expect(outcome.starsByGoalSlug, {'greet': 1});
    });

    test('is null when the archive did not happen (archivedAt null)', () {
      expect(
        ActivityAutoSaveService.buildSessionOutcome(
          sessionRoomId: '!s:x',
          activityId: 'act-1',
          archivedAt: null,
          sourceCourseId: null,
          loRefs: const [],
          starsByGoalSlug: const {},
        ),
        isNull,
      );
    });

    test('is null when there is no activity id', () {
      expect(build(activityId: null), isNull);
    });
  });

  group('activeAccountPublishesStars', () {
    // The services are per-account and all run at once, but they publish
    // through one global controller that resolves the ACTIVE account. Counting
    // a background account's rooms and publishing them under the active
    // account's profile would file A's stars on B — permanently, since a
    // published total is never lowered.
    const a = '@a:example.invalid';
    const b = '@b:example.invalid';

    test('the active account publishes', () {
      expect(
        activeAccountPublishesStars(serviceUserId: a, activeUserId: a),
        isTrue,
      );
    });

    test('a background account does not', () {
      expect(
        activeAccountPublishesStars(serviceUserId: a, activeUserId: b),
        isFalse,
      );
    });

    test('nothing publishes while an account is still resolving', () {
      expect(
        activeAccountPublishesStars(serviceUserId: null, activeUserId: a),
        isFalse,
      );
      expect(
        activeAccountPublishesStars(serviceUserId: a, activeUserId: null),
        isFalse,
      );
    });
  });
}

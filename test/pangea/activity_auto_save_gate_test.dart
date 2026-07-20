import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_auto_save_service.dart';
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
}

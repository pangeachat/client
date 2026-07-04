import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';

/// The single gate that decides whether a discovered session is "joinable".
///
/// Both surfaces read the *same* predicate so a pin the map shows joinable is
/// one the start page will actually offer a Join for (never a green pin that
/// dead-ends at "Start"): the world map's coursemate discovery skips
/// `isStarted` sessions, and the start page's open-session list keeps only
/// `isActivityOpenToJoin` (= `!isStarted`, given members + an activity id). See
/// world-map.instructions.md ("Discovering joinable sessions").
///
/// The full-but-not-finished case (all roles taken → `isStarted` true via the
/// seat count) is exercised on live data — a real full session previews as
/// `roles=2, joinedWithRoles=2 → isStarted=true` — and needs a heavy plan
/// fixture to reproduce synthetically; these tests lock the cheaper, subtler
/// contracts around it.
void main() {
  group('RoomSummaryResponse — the joinable / open-to-join gate', () {
    test('a thin-ref session (no embedded role plan) stays open: seats unknown '
        '→ permissive, so the seat check never hides a possibly-joinable v3 '
        'session', () {
      // A v3 preview carries only a thin { activity_id } ref, leaving
      // activityPlan null. isStarted must stay false so the map keeps surfacing
      // it exactly as before this refinement (no regression for thin-ref).
      final summary = RoomSummaryResponse(
        membershipSummary: {'@a:example.org': 'join'},
        activityId: 'act-1',
        activityPlan: null,
        activityRoles: null,
      );

      expect(summary.isStarted, isFalse);
      expect(summary.isActivityOpenToJoin, isTrue);
    });

    test(
      'a session with no members is not open to join (joining would error)',
      () {
        final summary = RoomSummaryResponse(
          membershipSummary: {},
          activityId: 'act-1',
        );

        expect(summary.isActivityOpenToJoin, isFalse);
      },
    );

    test('a room without an activity id is not an open activity session', () {
      final summary = RoomSummaryResponse(
        membershipSummary: {'@a:example.org': 'join'},
        activityId: null,
      );

      expect(summary.isActivityOpenToJoin, isFalse);
    });
  });
}

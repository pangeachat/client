import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/network/rate_limit_pause.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';

/// CLIENT-DQC (#8094): a missing quest is a state the repo classified benign —
/// [QuestRepo.quest] returns [MissingQuestException] without reporting, and the
/// course panel renders it as a known state — yet the world map's objective
/// cache rebuild reported it to Sentry at `error`, titled `Instance of
/// 'MissingQuestException'`. These pin both halves of the fix: a real
/// `toString()`, and the caller keeping the repo's classification (warning,
/// not error) while other outline failures stay errors.
///
/// #8470 reopened it: the rule reached the world map's reporter and not the
/// course panel's, and since both spend the SAME throttle key, whichever
/// surface the learner opened first decided the severity. Both now go through
/// the one [reportCourseOutlineFailure], whose budget is pinned below.
///
/// #8691 moved the missing-quest report itself into [QuestRepo.quest] (once
/// per quest id per session, at the actual fetch, with fetches capped by the
/// persisted removed verdict) — so this reporter now SKIPS
/// [MissingQuestException] entirely; its per-room budget below is pinned with
/// the other outline failures it still owns. The skip itself is pinned in
/// quest_plan_removed_persistence_test.dart.
void main() {
  test('MissingQuestException has a diagnosable toString', () {
    expect(
      MissingQuestException().toString(),
      'MissingQuestException: quest plan not found in CMS (confirmed 404)',
    );
  });

  group('courseOutlineErrorLevel', () {
    test('a missing quest reports at warning — repo classified it benign', () {
      expect(
        courseOutlineErrorLevel(MissingQuestException()),
        SentryLevel.warning,
      );
    });

    test('any other outline failure stays an error', () {
      expect(
        courseOutlineErrorLevel(Exception('choreo unreachable')),
        SentryLevel.error,
      );
    });
  });

  group('reportCourseOutlineFailure', () {
    setUp(ErrorHandler.resetReportedOnceKeysForTest);

    test('reports a course room once per session, then throttles', () async {
      // The documented budget (#8083): a course that persistently fails
      // re-fails on every rebuild — the map's self-heal retry and each
      // course-panel open — and every repeat after the first carries no new
      // signal. This is also what makes ONE shared reporter necessary rather
      // than merely tidy (#8470): the second surface to run is silent, so two
      // copies of the callback would not agree on severity, they would let
      // whichever ran first decide it.
      final first = await reportCourseOutlineFailure(
        '!room:server',
        'quest-1',
        Exception('choreo unreachable'),
        StackTrace.current,
      );
      final second = await reportCourseOutlineFailure(
        '!room:server',
        'quest-1',
        Exception('choreo unreachable'),
        StackTrace.current,
      );
      expect(first, isTrue);
      expect(second, isFalse);
    });

    test('spends a separate key per course room', () async {
      // Keyed per ROOM, not per quest: two rooms of one quest can fail
      // independently (#8087), so each is owed its own report.
      expect(
        await reportCourseOutlineFailure(
          '!r1:server',
          'quest-1',
          Exception('choreo unreachable'),
          StackTrace.current,
        ),
        isTrue,
      );
      expect(
        await reportCourseOutlineFailure(
          '!r2:server',
          'quest-1',
          Exception('choreo unreachable'),
          StackTrace.current,
        ),
        isTrue,
      );
    });

    // CLIENT-EAG / #8507: a rate-limit pause suppressing the read is the
    // repo's own deliberate, correct behavior, and the repo that returned it
    // already reported the suppression once for this activation
    // (RateLimitPause.reportSuppressionOnce). Reporting it again here, per
    // course room, would multiply one suppression event by however many
    // joined courses race the rebuild.
    test(
      'never reports a RateLimitedException — the repo already reported the suppression',
      () async {
        expect(
          await reportCourseOutlineFailure(
            '!room:server',
            'quest-1',
            RateLimitedException(),
            StackTrace.current,
          ),
          isFalse,
        );
      },
    );
  });
}

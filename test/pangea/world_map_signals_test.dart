import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/routes/world/world_map_signals.dart';

const int _dayMs = 24 * 60 * 60 * 1000;

ActivitySessionFacts _session(
  String activityId, {
  bool holdsRole = false,
  int collectedGoals = 0,
  int totalGoals = 0,
  bool joinable = false,
  int lastEventMs = 0,
  int numRemainingRoles = 0,
  bool ownRoleFinished = false,
}) => ActivitySessionFacts(
  activityId: activityId,
  holdsRole: holdsRole,
  collectedGoals: collectedGoals,
  totalGoals: totalGoals,
  joinable: joinable,
  lastEventMs: lastEventMs,
  numRemainingRoles: numRemainingRoles,
  ownRoleFinished: ownRoleFinished,
);

ActivityCompletionFacts _completion(
  String activityId, {
  required int totalGoals,
  required int collectedGoals,
}) => (
  activityId: activityId,
  totalGoals: totalGoals,
  collectedGoals: collectedGoals,
);

void main() {
  group('reduceActivitySignals', () {
    test(
      'a held role in a full-roster session reads ongoingActive, with the fraction',
      () {
        final s = WorldMapSignalUtils.reduceActivitySignals(
          [
            _session(
              'a',
              holdsRole: true,
              collectedGoals: 3,
              totalGoals: 4,
              numRemainingRoles: 0,
            ),
          ],
          pingedActivityIds: const {},
          nowMs: 0,
        );
        expect(s['a']!.state, ActivityPinState.ongoingActive);
        expect(s['a']!.completionFraction, closeTo(0.75, 1e-9));
      },
    );

    test(
      'a held role in a not-yet-full session reads ongoingPending',
      () {
        final s = WorldMapSignalUtils.reduceActivitySignals(
          [
            _session(
              'a',
              holdsRole: true,
              collectedGoals: 1,
              totalGoals: 4,
              numRemainingRoles: 2,
            ),
          ],
          pingedActivityIds: const {},
          nowMs: 0,
        );
        expect(s['a']!.state, ActivityPinState.ongoingPending);
        expect(s['a']!.completionFraction, closeTo(0.25, 1e-9));
      },
    );

    test('a completed held role emits no colour state (falls to stars)', () {
      // All own goals collected → not a live "resume" session, so the reducer
      // emits no state for it; the view layers inProgress (the gold trail star)
      // from the learner's stars instead of reading joined forever.
      final s = WorldMapSignalUtils.reduceActivitySignals(
        [_session('a', holdsRole: true, collectedGoals: 4, totalGoals: 4)],
        pingedActivityIds: const {},
        nowMs: 0,
      );
      expect(s.containsKey('a'), isFalse);
    });

    test(
      'a finished-but-archived held role emits no colour state, even with an '
      'incomplete star row',
      () {
        // Finished (and possibly archived) without collecting every star: not
        // a live "resume it" session, so it must not read ongoingActive
        // forever — same outcome as a fully-starred completion above.
        final s = WorldMapSignalUtils.reduceActivitySignals(
          [
            _session(
              'a',
              holdsRole: true,
              collectedGoals: 1,
              totalGoals: 4,
              numRemainingRoles: 0,
              ownRoleFinished: true,
            ),
          ],
          pingedActivityIds: const {},
          nowMs: 0,
        );
        expect(s.containsKey('a'), isFalse);
      },
    );

    test('keeps the BEST fraction across sessions of the same activity', () {
      final s = WorldMapSignalUtils.reduceActivitySignals(
        [
          _session('a', holdsRole: true, collectedGoals: 1, totalGoals: 4),
          _session('a', holdsRole: true, collectedGoals: 3, totalGoals: 4),
        ],
        pingedActivityIds: const {},
        nowMs: 0,
      );
      expect(s['a']!.completionFraction, closeTo(0.75, 1e-9));
    });

    test('total 0 yields 0 fraction (no divide-by-zero)', () {
      final s = WorldMapSignalUtils.reduceActivitySignals(
        [_session('a', holdsRole: true, collectedGoals: 0, totalGoals: 0)],
        pingedActivityIds: const {},
        nowMs: 0,
      );
      expect(s['a']!.completionFraction, 0);
    });

    test(
      'ongoing beats joinable on the colour ladder, fraction preserved',
      () {
        final s = WorldMapSignalUtils.reduceActivitySignals(
          [
            // one session where the user holds a role (ongoing, half done)…
            _session(
              'a',
              holdsRole: true,
              collectedGoals: 1,
              totalGoals: 2,
              numRemainingRoles: 0,
            ),
            // …and another, open, session of the same activity (joinable). The
            // learner's own live session wins the colour (ongoing > joinable).
            _session('a', joinable: true, lastEventMs: _dayMs),
          ],
          pingedActivityIds: const {},
          nowMs: _dayMs,
        );
        expect(s['a']!.state, ActivityPinState.ongoingActive);
        expect(s['a']!.completionFraction, closeTo(0.5, 1e-9));
      },
    );

    test('recency decays linearly from the newest open session over 24h', () {
      final fresh = WorldMapSignalUtils.reduceActivitySignals(
        [_session('a', joinable: true, lastEventMs: _dayMs)],
        pingedActivityIds: const {},
        nowMs: _dayMs, // age 0
      );
      expect(fresh['a']!.recency, closeTo(1.0, 1e-9));

      final half = WorldMapSignalUtils.reduceActivitySignals(
        [_session('a', joinable: true, lastEventMs: _dayMs ~/ 2)],
        pingedActivityIds: const {},
        nowMs: _dayMs, // age 12h
      );
      expect(half['a']!.recency, closeTo(0.5, 1e-9));

      final stale = WorldMapSignalUtils.reduceActivitySignals(
        [_session('a', joinable: true, lastEventMs: _dayMs)],
        pingedActivityIds: const {},
        nowMs: _dayMs * 3, // age 48h → clamped to 0
      );
      expect(stale['a']!.recency, 0);
    });

    test('the newest open session wins for recency', () {
      final s = WorldMapSignalUtils.reduceActivitySignals(
        [
          _session('a', joinable: true, lastEventMs: 1),
          _session('a', joinable: true, lastEventMs: _dayMs),
        ],
        pingedActivityIds: const {},
        nowMs: _dayMs,
      );
      expect(s['a']!.recency, closeTo(1.0, 1e-9));
    });

    test('pinged flag comes from pingedActivityIds', () {
      final s = WorldMapSignalUtils.reduceActivitySignals(
        [
          _session('a', joinable: true, lastEventMs: _dayMs),
          _session('b', joinable: true, lastEventMs: _dayMs),
        ],
        pingedActivityIds: const {'a'},
        nowMs: _dayMs,
      );
      expect(s['a']!.pinged, isTrue);
      expect(s['b']!.pinged, isFalse);
    });

    test(
      'a room with neither a held role nor a free slot contributes nothing',
      () {
        final s = WorldMapSignalUtils.reduceActivitySignals(
          [_session('a')],
          pingedActivityIds: const {},
          nowMs: 0,
        );
        expect(s, isEmpty);
      },
    );
  });

  group('reduceCompletion', () {
    test('all goals collected is completed', () {
      final m = WorldMapSignalUtils.reduceActivityCompletions([
        _completion('a', totalGoals: 3, collectedGoals: 3),
      ]);
      expect(m['a'], MapCompletionFilter.completed);
    });

    test('some goals collected is in-progress', () {
      final m = WorldMapSignalUtils.reduceActivityCompletions([
        _completion('a', totalGoals: 3, collectedGoals: 1),
      ]);
      expect(m['a'], MapCompletionFilter.inProgress);
    });

    test('total 0 is in-progress, never completed', () {
      final m = WorldMapSignalUtils.reduceActivityCompletions([
        _completion('a', totalGoals: 0, collectedGoals: 0),
      ]);
      expect(m['a'], MapCompletionFilter.inProgress);
    });

    test('the highest status across sessions wins', () {
      final m = WorldMapSignalUtils.reduceActivityCompletions([
        _completion('a', totalGoals: 3, collectedGoals: 1), // inProgress
        _completion('a', totalGoals: 3, collectedGoals: 3), // completed
      ]);
      expect(m['a'], MapCompletionFilter.completed);
    });
  });

  group('bandAtOrBelow', () {
    test('null level includes every CEFR level', () {
      expect(
        LanguageLevelTypeEnum.bandAtOrBelow(null),
        LanguageLevelTypeEnum.values.toSet(),
      );
    });

    test('a level includes itself and everything below, nothing above', () {
      final band = LanguageLevelTypeEnum.bandAtOrBelow(
        LanguageLevelTypeEnum.b1,
      );
      expect(
        band,
        containsAll([
          LanguageLevelTypeEnum.preA1,
          LanguageLevelTypeEnum.a1,
          LanguageLevelTypeEnum.a2,
          LanguageLevelTypeEnum.b1,
        ]),
      );
      expect(band, isNot(contains(LanguageLevelTypeEnum.b2)));
      expect(band, isNot(contains(LanguageLevelTypeEnum.c1)));
      expect(band, isNot(contains(LanguageLevelTypeEnum.c2)));
    });
  });
}

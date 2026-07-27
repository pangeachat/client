import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';

CourseLoOutline _outline(List<String> los, {String courseId = 'c1'}) =>
    CourseLoOutline(
      courseId: courseId,
      orderedLoIds: los,
      activityIdsByLo: const {},
    );

void main() {
  group('JoinedObjectiveCache.rebuild', () {
    test('ids and outlines start empty before any rebuild', () {
      final cache = JoinedObjectiveCache();
      expect(cache.ids, isEmpty);
      expect(cache.outlines, isEmpty);
    });

    test('unions and dedups objective ids across joined courses', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild(
        ['c1', 'c2'],
        outlineOf: (u) async =>
            _outline(u == 'c1' ? ['lo-a', 'lo-b'] : ['lo-b', 'lo-c']),
      );
      expect(cache.ids, {'lo-a', 'lo-b', 'lo-c'});
      expect(cache.outlines.length, 2);
    });

    test('keeps each course outline ordered for the gate', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild([
        'c1',
      ], outlineOf: (u) async => _outline(['lo-1', 'lo-2', 'lo-3']));
      expect(cache.outlines.single.orderedLoIds, ['lo-1', 'lo-2', 'lo-3']);
    });

    test('applies the per-course stars-to-unlock override', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild(
        ['c1'],
        outlineOf: (u) async => _outline(['lo-a']),
        starsToUnlockOf: (u) => 5,
      );
      expect(cache.outlines.single.starsToUnlock, 5);
    });

    test('defaults the threshold when no override is given', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild(['c1'], outlineOf: (u) async => _outline(['lo-a']));
      expect(
        cache.outlines.single.starsToUnlock,
        kDefaultStarsToUnlockObjective,
      );
    });

    test(
      'skips a course that fails to resolve, reporting it via onError',
      () async {
        final cache = JoinedObjectiveCache();
        final failed = <String>[];
        await cache.rebuild(
          ['ok', 'bad'],
          outlineOf: (u) async {
            if (u == 'bad') throw Exception('boom');
            return _outline(['lo-a']);
          },
          onError: (uuid, e, s) => failed.add(uuid),
        );
        expect(cache.ids, {'lo-a'});
        expect(cache.outlines.length, 1);
        // The failure is surfaced, not swallowed (a silently-empty cache is the
        // exact failure mode this guards against).
        expect(failed, ['bad']);
      },
    );

    test('is empty with no joined courses', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild(const [], outlineOf: (u) async => _outline(['x']));
      expect(cache.ids, isEmpty);
      expect(cache.outlines, isEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/joined_objective_cache.dart';

void main() {
  group('JoinedObjectiveCache.rebuild', () {
    test('ids start empty before any rebuild', () {
      expect(JoinedObjectiveCache().ids, isEmpty);
    });

    test('unions and dedups objective ids across joined courses', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild(
        ['c1', 'c2'],
        objectivesOf: (u) async =>
            u == 'c1' ? ['lo-a', 'lo-b'] : ['lo-b', 'lo-c'],
      );
      expect(cache.ids, {'lo-a', 'lo-b', 'lo-c'});
    });

    test('skips a course that fails to resolve, keeping the rest', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild(
        ['ok', 'bad'],
        objectivesOf: (u) async {
          if (u == 'bad') throw Exception('boom');
          return ['lo-a'];
        },
      );
      expect(cache.ids, {'lo-a'});
    });

    test('is empty with no joined courses', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild(const [], objectivesOf: (u) async => ['x']);
      expect(cache.ids, isEmpty);
    });
  });
}

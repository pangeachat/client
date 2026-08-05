import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map_pins_manager.dart';

void main() {
  // #8083: the empty-cache self-heal used to re-fire on every rate-limited
  // sync for a learner whose joined courses are all unresolvable (e.g.
  // orphaned quest plans), refetching and re-logging in a loop. The pure rule
  // paces that retry by kEmptyObjectiveCacheRetryCooldown while leaving
  // set-change rebuilds (course join/leave) immediate.
  group('shouldRebuildObjectiveCacheNow', () {
    final now = DateTime(2026, 8, 3, 12);

    test('never rebuilds while a rebuild is in flight', () {
      expect(
        shouldRebuildObjectiveCacheNow(
          rebuilding: true,
          setChanged: true,
          emptyButHasCourses: true,
          lastRebuildAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('a set change rebuilds immediately, cooldown or not', () {
      expect(
        shouldRebuildObjectiveCacheNow(
          rebuilding: false,
          setChanged: true,
          emptyButHasCourses: false,
          lastRebuildAt: now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        isTrue,
      );
    });

    test('a populated, unchanged cache does not rebuild', () {
      expect(
        shouldRebuildObjectiveCacheNow(
          rebuilding: false,
          setChanged: false,
          emptyButHasCourses: false,
          lastRebuildAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('the empty-cache retry is due when no rebuild has run', () {
      expect(
        shouldRebuildObjectiveCacheNow(
          rebuilding: false,
          setChanged: false,
          emptyButHasCourses: true,
          lastRebuildAt: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('the empty-cache retry waits out the cooldown', () {
      expect(
        shouldRebuildObjectiveCacheNow(
          rebuilding: false,
          setChanged: false,
          emptyButHasCourses: true,
          lastRebuildAt: now.subtract(
            kEmptyObjectiveCacheRetryCooldown - const Duration(seconds: 1),
          ),
          now: now,
        ),
        isFalse,
      );
    });

    test('the empty-cache retry fires once the cooldown has passed', () {
      expect(
        shouldRebuildObjectiveCacheNow(
          rebuilding: false,
          setChanged: false,
          emptyButHasCourses: true,
          lastRebuildAt: now.subtract(kEmptyObjectiveCacheRetryCooldown),
          now: now,
        ),
        isTrue,
      );
    });
  });
}

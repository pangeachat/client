import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/lo_progression.dart';

void main() {
  CourseLoOutline course(
    List<String> seq, {
    Map<String, Set<String>> acts = const {},
    int threshold = kDefaultStarsToUnlockObjective,
  }) => CourseLoOutline(
    orderedLoIds: seq,
    activityIdsByLo: acts,
    starsToUnlock: threshold,
  );

  group('buildLoGate', () {
    test('first objective is always unlocked, the rest start locked', () {
      final gate = buildLoGate(
        outlines: [
          course(
            ['lo1', 'lo2', 'lo3'],
            acts: {
              'lo1': {'a1'},
              'lo2': {'a2'},
              'lo3': {'a3'},
            },
          ),
        ],
        starsByActivity: const {},
      );
      expect(gate.unlocked, {'lo1'});
      expect(gate.gated, {'lo1', 'lo2', 'lo3'});
    });

    test('10 stars in the previous objective unlocks the next', () {
      final gate = buildLoGate(
        outlines: [
          course(
            ['lo1', 'lo2'],
            acts: {
              'lo1': {'a1'},
              'lo2': {'a2'},
            },
          ),
        ],
        starsByActivity: const {'a1': 10},
      );
      expect(gate.unlocked, {'lo1', 'lo2'});
    });

    test('stars below the threshold leave the next objective locked', () {
      final gate = buildLoGate(
        outlines: [
          course(
            ['lo1', 'lo2'],
            acts: {
              'lo1': {'a1'},
              'lo2': {'a2'},
            },
          ),
        ],
        starsByActivity: const {'a1': 9},
      );
      expect(gate.unlocked, {'lo1'});
    });

    test("stars sum across the objective's activities", () {
      final gate = buildLoGate(
        outlines: [
          course(
            ['lo1', 'lo2'],
            acts: {
              'lo1': {'a1', 'a2'},
              'lo2': {'a3'},
            },
          ),
        ],
        starsByActivity: const {'a1': 6, 'a2': 4},
      );
      expect(gate.unlocked, contains('lo2'));
    });

    test('a teacher override changes the threshold', () {
      final gate = buildLoGate(
        outlines: [
          course(
            ['lo1', 'lo2'],
            acts: {
              'lo1': {'a1'},
              'lo2': {'a2'},
            },
            threshold: 3,
          ),
        ],
        starsByActivity: const {'a1': 3},
      );
      expect(gate.unlocked, {'lo1', 'lo2'});
    });

    test('an objective unlocked along any course sequence wins', () {
      final gate = buildLoGate(
        outlines: [
          // course A locks 'shared' (its predecessor 'x' is unsatisfied)…
          course(
            ['x', 'shared'],
            acts: {
              'x': {'ax'},
              'shared': {'as'},
            },
          ),
          // …but course B places 'shared' first, so it unlocks.
          course(
            ['shared'],
            acts: {
              'shared': {'as'},
            },
          ),
        ],
        starsByActivity: const {},
      );
      expect(gate.unlocked, contains('shared'));
    });
  });

  group('LoProgressionGate.isPinLocked', () {
    const gate = LoProgressionGate(
      unlocked: {'lo1'},
      gated: {'lo1', 'lo2'},
    );

    test('a pin whose only objective is locked reads locked', () {
      expect(gate.isPinLocked(['lo2']), isTrue);
    });

    test('a pin with any unlocked objective is not locked', () {
      expect(gate.isPinLocked(['lo2', 'lo1']), isFalse);
    });

    test('an ungated pin (no gated objective) is never locked', () {
      expect(gate.isPinLocked(['global-lo']), isFalse);
      expect(gate.isPinLocked(const []), isFalse);
    });
  });
}

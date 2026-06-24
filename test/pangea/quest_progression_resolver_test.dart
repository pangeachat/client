import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';

void main() {
  CourseLoOutline outline(
    List<String> seq,
    Map<String, Set<String>> acts, {
    int threshold = kDefaultStarsToUnlockObjective,
  }) => CourseLoOutline(
    orderedLoIds: seq,
    activityIdsByLo: acts,
    starsToUnlock: threshold,
  );

  group('resolveProgression — rollup', () {
    test("sums a Mission's stars across its activities", () {
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1'],
            {
              'm1': {'a', 'b'},
            },
          ),
        ],
        starsByActivity: {'a': 3, 'b': 4},
      );
      expect(r.rollup['m1']!.stars, 7);
      expect(r.rollup['m1']!.threshold, 10);
      expect(r.rollup['m1']!.satisfied, isFalse);
    });

    test('an activity serving two Missions counts toward each', () {
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1', 'm2'],
            {
              'm1': {'a'},
              'm2': {'a'},
            },
          ),
        ],
        starsByActivity: {'a': 5},
      );
      expect(r.rollup['m1']!.stars, 5);
      expect(r.rollup['m2']!.stars, 5);
    });

    test('a shared activity across quests is unioned, not double-counted', () {
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1'],
            {
              'm1': {'a'},
            },
          ),
          outline(
            ['m1'],
            {
              'm1': {'a'},
            },
          ),
        ],
        starsByActivity: {'a': 6},
      );
      expect(r.rollup['m1']!.stars, 6); // unioned, not 12
    });
  });

  group('resolveProgression — anchor', () {
    test('the first below-threshold Mission is the anchor', () {
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1', 'm2', 'm3'],
            {
              'm1': {'a'},
              'm2': {'b'},
              'm3': {'c'},
            },
          ),
        ],
        starsByActivity: {'a': 10}, // m1 satisfied -> m2 is next
      );
      expect(r.quests.single.anchorMissionId, 'm2');
    });

    test('all satisfied -> lowest-star Mission, earliest-order tie-break', () {
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1', 'm2', 'm3'],
            {
              'm1': {'a'},
              'm2': {'b'},
              'm3': {'c'},
            },
          ),
        ],
        // all >= 10; m2 & m3 tie for lowest (10) -> earliest wins (m2)
        starsByActivity: {'a': 15, 'b': 10, 'c': 10},
      );
      expect(r.quests.single.anchorMissionId, 'm2');
    });

    test('an empty sequence yields no quest entry', () {
      final r = resolveProgression(
        outlines: [outline([], {})],
        starsByActivity: {},
      );
      expect(r.quests, isEmpty);
    });
  });

  group('missionGradient', () {
    final r = resolveProgression(
      outlines: [
        outline(
          ['m1', 'm2', 'm3', 'm4', 'm5'],
          {
            'm1': {'a1'},
            'm2': {'a2'},
            'm3': {'a3'},
            'm4': {'a4'},
            'm5': {'a5'},
          },
        ),
      ],
      starsByActivity: {}, // nothing satisfied -> anchor = m1
    );

    test('peaks at the anchor and decays linearly to zero', () {
      expect(r.missionGradient(['m1']), closeTo(1.0, 1e-9)); // anchor
      expect(r.missionGradient(['m2']), closeTo(1 - 1 / 3, 1e-9));
      expect(r.missionGradient(['m3']), closeTo(1 - 2 / 3, 1e-9));
      expect(r.missionGradient(['m4']), 0); // 3 Missions past the anchor
      expect(r.missionGradient(['m5']), 0);
    });

    test('a satisfied Mission contributes ~0', () {
      final r2 = resolveProgression(
        outlines: [
          outline(
            ['m1', 'm2'],
            {
              'm1': {'a1'},
              'm2': {'a2'},
            },
          ),
        ],
        starsByActivity: {'a1': 10}, // m1 satisfied -> anchor = m2
      );
      expect(r2.missionGradient(['m1']), 0); // satisfied
      expect(r2.missionGradient(['m2']), closeTo(1.0, 1e-9)); // anchor
    });

    test('contributions sum across quests and saturate at the ceiling', () {
      final multi = resolveProgression(
        outlines: [
          outline(
            ['q1m1'],
            {
              'q1m1': {'x'},
            },
          ),
          outline(
            ['q2m1'],
            {
              'q2m1': {'y'},
            },
          ),
          outline(
            ['q3m1'],
            {
              'q3m1': {'z'},
            },
          ),
        ],
        starsByActivity: {},
      );
      // one activity carrying all three anchors: 1+1+1 = 3, saturated to 2
      expect(multi.missionGradient(['q1m1', 'q2m1', 'q3m1']), kBandCeiling);
    });

    test('refs outside any quest -> 0 (consumer falls back to plain fit)', () {
      expect(r.missionGradient(['unknown']), 0);
    });

    test('the empty resolution is fail-soft (always 0)', () {
      expect(ProgressionResolution.empty.missionGradient(['m1']), 0);
    });
  });
}

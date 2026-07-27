import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';

void main() {
  CourseLoOutline outline(
    List<String> seq,
    Map<String, Set<String>> acts, {
    String courseId = 'c1',
    int threshold = kDefaultStarsToUnlockObjective,
    Map<String, int> earnable = const {},
  }) => CourseLoOutline(
    courseId: courseId,
    orderedLoIds: seq,
    activityIdsByLo: acts,
    starsToUnlock: threshold,
    earnableByActivity: earnable,
  );

  /// Rollups are per course (#7771); these single-course cases read 'c1'.
  Map<String, MissionProgress> rollupOf(
    ProgressionResolution r, [
    String courseId = 'c1',
  ]) => r.forCourse(courseId)!.rollup;

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
      expect(rollupOf(r)['m1']!.stars, 7);
      expect(rollupOf(r)['m1']!.threshold, 10);
      expect(rollupOf(r)['m1']!.satisfied, isFalse);
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
      expect(rollupOf(r)['m1']!.stars, 5);
      expect(rollupOf(r)['m2']!.stars, 5);
    });

    test('an activity shared by two quests is never double-counted', () {
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1'],
            {
              'm1': {'a'},
            },
            courseId: 'c1',
          ),
          outline(
            ['m1'],
            {
              'm1': {'a'},
            },
            courseId: 'c2',
          ),
        ],
        starsByActivity: {'a': 6},
      );
      // Each course counts the shared activity once, in its own rollup — 6,
      // never 12. Per-course resolution gets this without a union (#7771).
      expect(rollupOf(r, 'c1')['m1']!.stars, 6);
      expect(rollupOf(r, 'c2')['m1']!.stars, 6);
    });
  });

  group('resolveProgression — effective threshold clamp', () {
    test('threshold clamps to the sum of earnable stars across activities', () {
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1'],
            {
              'm1': {'a', 'b'},
            },
            earnable: {'a': 3, 'b': 4},
          ),
        ],
        starsByActivity: {},
      );
      // configured 10, content offers 3 + 4 = 7
      expect(rollupOf(r)['m1']!.threshold, 7);
    });

    test('a configured threshold below the ceiling is kept as-is', () {
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1'],
            {
              'm1': {'a', 'b'},
            },
            threshold: 5,
            earnable: {'a': 3, 'b': 4},
          ),
        ],
        starsByActivity: {},
      );
      expect(rollupOf(r)['m1']!.threshold, 5);
    });

    test('a zero ceiling (no goal data) leaves the configured threshold', () {
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1'],
            {
              'm1': {'a'},
            },
          ),
        ],
        starsByActivity: {},
      );
      // no earnable data — do NOT clamp to 0 (a Mission must not read
      // satisfied-at-zero off degraded/legacy plans)
      expect(rollupOf(r)['m1']!.threshold, kDefaultStarsToUnlockObjective);
      expect(rollupOf(r)['m1']!.satisfied, isFalse);
    });

    test('a Mission satisfiable only via the clamp reads satisfied', () {
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1', 'm2'],
            {
              'm1': {'a'},
              'm2': {'b'},
            },
            earnable: {'a': 4, 'b': 4},
          ),
        ],
        starsByActivity: {'a': 4}, // full marks on m1's only activity
      );
      expect(rollupOf(r)['m1']!.satisfied, isTrue);
      // and the anchor advances past it
      expect(r.quests.single.anchorMissionId, 'm2');
    });

    test('each course clamps against its own earnable data', () {
      // Outlines carry the same plan, so earnable values should agree; if they
      // ever disagree, each course clamps against what its OWN outline says
      // rather than inheriting the other's ceiling (#7771).
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1'],
            {
              'm1': {'a'},
            },
            courseId: 'c1',
            earnable: {'a': 4},
          ),
          outline(
            ['m1'],
            {
              'm1': {'a'},
            },
            courseId: 'c2',
            earnable: {'a': 3},
          ),
        ],
        starsByActivity: {},
      );
      expect(rollupOf(r, 'c1')['m1']!.threshold, 4);
      expect(rollupOf(r, 'c2')['m1']!.threshold, 3);
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
            courseId: 'c1',
          ),
          outline(
            ['q2m1'],
            {
              'q2m1': {'y'},
            },
            courseId: 'c2',
          ),
          outline(
            ['q3m1'],
            {
              'q3m1': {'z'},
            },
            courseId: 'c3',
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

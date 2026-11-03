import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/can_do_progress.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';

void main() {
  CourseLoOutline outline(
    List<String> seq,
    Map<String, Set<String>> acts, {
    String courseId = 'c1',
    // The scenarios are sized to a 300 XP threshold; the shipped default
    // (the Standard preset) is not what they test.
    int xpToComplete = 300,
  }) => CourseLoOutline(
    courseId: courseId,
    orderedLoIds: seq,
    activityIdsByLo: acts,
    xpToComplete: xpToComplete,
  );

  /// Rollups are per course (#7771); these single-course cases read 'c1'.
  Map<String, MissionProgress> rollupOf(
    ProgressionResolution r, [
    String courseId = 'c1',
  ]) => r.forCourse(courseId)!.rollup;

  group('resolveProgression — rollup', () {
    test("sums a Mission's XP across its activities", () {
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1'],
            {
              'm1': {'a', 'b'},
            },
          ),
        ],
        xpByActivity: {'a': 120, 'b': 150},
      );
      expect(rollupOf(r)['m1']!.xp, 270);
      expect(rollupOf(r)['m1']!.threshold, 300);
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
        xpByActivity: {'a': 50},
      );
      expect(rollupOf(r)['m1']!.xp, 50);
      expect(rollupOf(r)['m2']!.xp, 50);
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
        xpByActivity: {'a': 60},
      );
      // Each course counts the shared activity once, in its own rollup — 60,
      // never 120. Per-course resolution gets this without a union (#7771).
      expect(rollupOf(r, 'c1')['m1']!.xp, 60);
      expect(rollupOf(r, 'c2')['m1']!.xp, 60);
    });

    test('the threshold is the outline\'s, with surplus XP shown raw', () {
      final r = resolveProgression(
        outlines: [
          outline(
            ['m1'],
            {
              'm1': {'a'},
            },
            xpToComplete: 200,
          ),
        ],
        xpByActivity: {'a': 340},
      );
      expect(rollupOf(r)['m1']!.threshold, 200);
      expect(rollupOf(r)['m1']!.xp, 340);
      expect(rollupOf(r)['m1']!.satisfied, isTrue);
      expect(rollupOf(r)['m1']!.fraction, 1.0);
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
        xpByActivity: {'a': 300}, // m1 satisfied -> m2 is next
      );
      expect(r.quests.single.anchorMissionId, 'm2');
      expect(r.quests.single.anchorProgress?.xp, 0);
      expect(r.quests.single.anchorProgress?.threshold, 300);
    });

    test('a fully satisfied quest has no anchor — nothing is Up next', () {
      // #8997: the anchor used to fall back to the weakest Mission, so a
      // learner who had completed every Mission still saw "Up next" on work
      // done.
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
        xpByActivity: {'a': 450, 'b': 300, 'c': 300}, // all >= 300
      );
      expect(r.quests.single.anchorMissionId, isNull);
      expect(r.quests.single.anchorProgress, isNull);
    });

    test('an empty sequence yields no quest entry', () {
      final r = resolveProgression(
        outlines: [outline([], {})],
        xpByActivity: {},
      );
      expect(r.quests, isEmpty);
    });
  });

  group('completedMissionIds', () {
    final r = resolveProgression(
      outlines: [
        outline(
          ['m1', 'm2'],
          {
            'm1': {'a'},
            'm2': {'b'},
          },
          courseId: 'c1',
        ),
        outline(
          ['m1', 'm3'],
          {
            'm1': {'a'},
            'm3': {'c'},
          },
          courseId: 'c2',
        ),
      ],
      xpByActivity: {'a': 300, 'c': 300},
    );

    test('a Mission satisfied in two courses is one star, not two', () {
      expect(r.completedMissionIds(), {'m1', 'm3'});
    });

    test('inScope narrows to the passing courses', () {
      expect(r.completedMissionIds(inScope: (c) => c == 'c1'), {'m1'});
      expect(r.completedMissionIds(inScope: (_) => false), isEmpty);
    });

    test('the empty resolution has none', () {
      expect(ProgressionResolution.empty.completedMissionIds(), isEmpty);
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
      xpByActivity: {}, // nothing satisfied -> anchor = m1
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
        xpByActivity: {'a1': 300}, // m1 satisfied -> anchor = m2
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
        xpByActivity: {},
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

  // A completed Mission stays complete (client#9681).
  group('resolveProgression — recorded completions', () {
    final completedAt = DateTime.utc(2026, 10, 20);

    CanDoProgress entry({
      DateTime? firstCompletedAt,
      int? xpToCompleteAtFirstCompletion,
      bool completedBeforeTracking = false,
    }) => CanDoProgress(
      xp: 0,
      breakdown: MissionXpBreakdown.zero,
      completed: true,
      firstCompletedAt: firstCompletedAt,
      completedBeforeTracking: completedBeforeTracking,
      xpToCompleteAtFirstCompletion: xpToCompleteAtFirstCompletion,
    );

    ProgressionResolution resolve(
      Map<String, Map<String, CanDoProgress>> recordedByCourse,
    ) => resolveProgression(
      outlines: [
        outline(
          ['m1', 'm2'],
          {
            'm1': {'a'},
            'm2': {'b'},
          },
          xpToComplete: 1500,
        ),
      ],
      xpByActivity: {'a': 600},
      recordedByCourse: recordedByCourse,
    );

    test('stays complete after the threshold rises, against its own', () {
      final r = resolve({
        'c1': {
          'm1': entry(
            firstCompletedAt: completedAt,
            xpToCompleteAtFirstCompletion: 500,
          ),
        },
      });
      final m1 = rollupOf(r)['m1']!;
      expect(m1.satisfied, isTrue);
      expect(m1.threshold, 500);
      expect(m1.fraction, 1.0);
      expect(r.forCourse('c1')!.anchorMissionId, 'm2');
      expect(r.completedMissionIds(), {'m1'});
    });

    test('without a stored threshold, counts against the course\'s', () {
      final m1 = rollupOf(
        resolve({
          'c1': {'m1': entry(firstCompletedAt: completedAt)},
        }),
      )['m1']!;
      expect(m1.satisfied, isTrue);
      expect(m1.threshold, 1500);
      expect(m1.fraction, closeTo(0.4, 1e-9));
    });

    test('an undated entry does not keep a Mission complete', () {
      final r = resolve({
        'c1': {'m1': entry(completedBeforeTracking: true)},
      });
      expect(rollupOf(r)['m1']!.satisfied, isFalse);
      expect(r.forCourse('c1')!.anchorMissionId, 'm1');
    });

    test('another course\'s record does not count', () {
      final r = resolve({
        'c2': {'m1': entry(firstCompletedAt: completedAt)},
      });
      expect(rollupOf(r)['m1']!.satisfied, isFalse);
    });
  });
}

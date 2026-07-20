import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';

/// Missions are a shared catalog reused across quests, so two joined courses
/// routinely carry the SAME Mission with DIFFERENT activities. The rollup is
/// resolved per course outline for exactly that reason: a global union would
/// clamp one course's threshold against another course's content and credit
/// its stars. See quests.instructions.md ("Star display on the course panel").
void main() {
  CourseLoOutline outline(
    String courseId,
    List<String> seq,
    Map<String, Set<String>> acts, {
    int threshold = kDefaultStarsToUnlockObjective,
    Map<String, int> earnable = const {},
  }) => CourseLoOutline(
    courseId: courseId,
    orderedLoIds: seq,
    activityIdsByLo: acts,
    starsToUnlock: threshold,
    earnableByActivity: earnable,
  );

  /// Course A pins Mission m1 to a single 4-star activity; course B carries the
  /// same Mission with its own, different 4-star activity.
  List<CourseLoOutline> sharedMissionCourses() => [
    outline(
      'A',
      ['m1'],
      {
        'm1': {'a1'},
      },
      earnable: {'a1': 4},
    ),
    outline(
      'B',
      ['m1'],
      {
        'm1': {'b1'},
      },
      earnable: {'b1': 4},
    ),
  ];

  group('per-course scoping', () {
    test("a course's threshold clamps to its OWN activities", () {
      final r = resolveProgression(
        outlines: sharedMissionCourses(),
        starsByActivity: const {},
      );

      expect(r.forCourse('A')!.rollup['m1']!.threshold, 4);
      expect(r.forCourse('B')!.rollup['m1']!.threshold, 4);
    });

    test("a course does not credit another course's stars", () {
      final r = resolveProgression(
        outlines: sharedMissionCourses(),
        starsByActivity: const {'b1': 3},
      );

      expect(r.forCourse('A')!.rollup['m1']!.stars, 0);
      expect(r.forCourse('B')!.rollup['m1']!.stars, 3);
    });

    test('an activity listed by BOTH courses still counts in each', () {
      // The union's legitimate job — the same activity satisfying a shared
      // Mission — survives scoping, because each outline lists it itself.
      final r = resolveProgression(
        outlines: [
          outline(
            'A',
            ['m1'],
            {
              'm1': {'shared'},
            },
            earnable: {'shared': 4},
          ),
          outline(
            'B',
            ['m1'],
            {
              'm1': {'shared'},
            },
            earnable: {'shared': 4},
          ),
        ],
        starsByActivity: const {'shared': 2},
      );

      expect(r.forCourse('A')!.rollup['m1']!.stars, 2);
      expect(r.forCourse('B')!.rollup['m1']!.stars, 2);
    });

    test(
      "a Mission satisfied in one course does not advance another's anchor",
      () {
        final r = resolveProgression(
          outlines: [
            outline(
              'A',
              ['m1', 'm2'],
              {
                'm1': {'a1'},
                'm2': {'a2'},
              },
              earnable: {'a1': 4, 'a2': 4},
            ),
            outline(
              'B',
              ['m1'],
              {
                'm1': {'b1'},
              },
              earnable: {'b1': 4},
            ),
          ],
          // Fully satisfies course B's m1; course A's m1 is untouched.
          starsByActivity: const {'b1': 4},
        );

        expect(r.forCourse('A')!.anchorMissionId, 'm1');
        expect(r.forCourse('B')!.rollup['m1']!.satisfied, isTrue);
      },
    );

    test('an unknown course resolves to no quest', () {
      final r = resolveProgression(
        outlines: sharedMissionCourses(),
        starsByActivity: const {},
      );

      expect(r.forCourse('never-joined'), isNull);
    });
  });

  group('questStars is scoped to its course', () {
    test("sums only the asking course's Missions", () {
      final r = resolveProgression(
        outlines: sharedMissionCourses(),
        starsByActivity: const {'b1': 4},
      );

      final a = r.questStars('A', ['m1']);
      expect(a.earned, 0);
      expect(a.total, 4, reason: "clamped to course A's own content");

      final b = r.questStars('B', ['m1']);
      expect(b.earned, 4);
      expect(b.total, 4);
    });

    test('an unresolved course falls back to the default denominator', () {
      // Preview / pre-resolve: a stable denominator, never another course's.
      final summary = ProgressionResolution.empty.questStars('A', ['m1', 'm2']);
      expect(summary.earned, 0);
      expect(summary.total, kDefaultStarsToUnlockObjective * 2);
    });
  });

  group('the world map band still accumulates across quests', () {
    test('an activity carrying two quests\' anchors sums their gradients', () {
      final r = resolveProgression(
        outlines: [
          outline(
            'A',
            ['m1'],
            {
              'm1': {'x'},
            },
          ),
          outline(
            'B',
            ['m2'],
            {
              'm2': {'x'},
            },
          ),
        ],
        starsByActivity: const {},
      );

      expect(r.missionGradient(['m1', 'm2']), 2.0);
    });

    test('a Mission satisfied in its own quest drops out of the band', () {
      final r = resolveProgression(
        outlines: [
          outline(
            'A',
            ['m1'],
            {
              'm1': {'a1'},
            },
            earnable: {'a1': 4},
          ),
        ],
        starsByActivity: const {'a1': 4},
      );

      expect(r.missionGradient(['m1']), 0.0);
    });
  });
}

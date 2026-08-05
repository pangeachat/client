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
    String? questId,
    int threshold = kDefaultStarsToUnlockObjective,
    Map<String, int> earnable = const {},
  }) => CourseLoOutline(
    courseId: courseId,
    questId: questId,
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

      final a = r.questStars('A')!;
      expect(a.earned, 0);
      expect(a.total, 4, reason: "clamped to course A's own content");

      final b = r.questStars('B')!;
      expect(b.earned, 4);
      expect(b.total, 4);
    });

    test('an unresolved course is null, not an invented denominator', () {
      expect(ProgressionResolution.empty.questStars('A'), isNull);
    });
  });

  group('activity-less Missions (#7663)', () {
    /// TigToggle's report: a quest whose sequence carries five Missions but
    /// where only one has an activity (worth 4 stars). The panel renders that
    /// one Mission; the header used to sum all five and add the default
    /// threshold for each hidden one — displaying 44.
    ProgressionResolution oneRealMissionOfFive() => resolveProgression(
      outlines: [
        outline(
          'A',
          ['m1', 'm2', 'm3', 'm4', 'm5'],
          {
            'm1': {'a1'},
          },
          earnable: {'a1': 4},
        ),
      ],
      starsByActivity: const {},
    );

    test('do not inflate the quest denominator (was 44, must be 4)', () {
      final summary = oneRealMissionOfFive().questStars('A')!;
      expect(summary.total, 4);
      expect(summary.earned, 0);
    });

    test('are absent from the rollup, so the panel has nothing to render', () {
      final quest = oneRealMissionOfFive().forCourse('A')!;
      expect(quest.rollup.keys, ['m1']);
      expect(quest.rollup['m2'], isNull);
    });

    test('never become the anchor — there is nothing to play there', () {
      // m1 is unsatisfied, so it anchors. Once it IS satisfied, the anchor must
      // not fall through to an unplayable Mission.
      final satisfied = resolveProgression(
        outlines: [
          outline(
            'A',
            ['m1', 'm2'],
            {
              'm1': {'a1'},
            },
            earnable: {'a1': 4},
          ),
        ],
        starsByActivity: const {'a1': 4},
      );
      expect(satisfied.forCourse('A')!.anchorMissionId, 'm1');
    });

    test('a quest with no playable Mission has no anchor at all', () {
      final none = resolveProgression(
        outlines: [
          outline('A', ['m1', 'm2'], const {}),
        ],
        starsByActivity: const {},
      );
      expect(none.forCourse('A')!.anchorMissionId, isNull);
      expect(none.questStars('A')!.total, 0);
    });

    test('a Mission WITH activities but no goal data keeps its threshold', () {
      // Distinct from the activity-less case: degraded/legacy plans report 0
      // earnable, and must NOT read satisfied-at-zero.
      final degraded = resolveProgression(
        outlines: [
          outline(
            'A',
            ['m1'],
            {
              'm1': {'a1'},
            },
          ),
        ],
        starsByActivity: const {},
      );
      final m1 = degraded.forCourse('A')!.rollup['m1']!;
      expect(m1.threshold, kDefaultStarsToUnlockObjective);
      expect(m1.satisfied, isFalse);
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

  group('two course rooms from one quest (#8087)', () {
    /// One quest ('q1') launched into two course rooms: room A pins Mission m1
    /// to its own 4-star activity, room B carries the same Mission with a
    /// different (side-quest) activity. Courses are keyed by room id; the
    /// shared quest uuid is the second key the band dedupes by.
    List<CourseLoOutline> twoRoomsOneQuest() => [
      outline(
        '!roomA:x',
        ['m1'],
        {
          'm1': {'a1'},
        },
        questId: 'q1',
        earnable: {'a1': 4},
      ),
      outline(
        '!roomB:x',
        ['m1'],
        {
          'm1': {'b1'},
        },
        questId: 'q1',
        earnable: {'b1': 4},
      ),
    ];

    test('each room resolves its own rollup — no last-room-wins collapse', () {
      final r = resolveProgression(
        outlines: twoRoomsOneQuest(),
        starsByActivity: const {'a1': 3},
      );

      expect(r.forCourse('!roomA:x')!.rollup['m1']!.stars, 3);
      expect(r.forCourse('!roomB:x')!.rollup['m1']!.stars, 0);
    });

    test("stars earned in one room's activity never credit the other", () {
      // The reported repro: earn stars in course B, course A displayed them.
      final r = resolveProgression(
        outlines: twoRoomsOneQuest(),
        starsByActivity: const {'b1': 2},
      );

      final a = r.questStars('!roomA:x')!;
      expect(a.earned, 0);
      final b = r.questStars('!roomB:x')!;
      expect(b.earned, 2);
    });

    test('the band counts the shared quest once, not once per room', () {
      final r = resolveProgression(
        outlines: twoRoomsOneQuest(),
        starsByActivity: const {},
      );

      expect(r.missionGradient(['m1']), 1.0);
    });

    test("a Mission satisfied in one room keeps the other room's signal", () {
      // Room A's m1 is satisfied (contribution 0); room B's differently-pinned
      // m1 is not. The quest's strongest per-room value stands (max, not
      // first-wins): the activity genuinely is the learner's next step in B.
      final r = resolveProgression(
        outlines: twoRoomsOneQuest(),
        starsByActivity: const {'a1': 4},
      );

      expect(r.missionGradient(['m1']), 1.0);
    });

    test('distinct quests with explicit questIds still sum', () {
      final r = resolveProgression(
        outlines: [
          outline(
            '!roomA:x',
            ['m1'],
            {
              'm1': {'x'},
            },
            questId: 'q1',
          ),
          outline(
            '!roomB:x',
            ['m2'],
            {
              'm2': {'x'},
            },
            questId: 'q2',
          ),
        ],
        starsByActivity: const {},
      );

      expect(r.missionGradient(['m1', 'm2']), 2.0);
    });
  });
}

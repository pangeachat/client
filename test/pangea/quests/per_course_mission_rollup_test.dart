import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';

/// Missions are a shared catalog reused across quests, so two joined courses
/// routinely carry the SAME Mission with DIFFERENT activities. The rollup is
/// resolved per course outline for exactly that reason: a global union would
/// credit one course's XP to another course's content. See
/// quests.instructions.md ("Star display on the course panel").
void main() {
  CourseLoOutline outline(
    String courseId,
    List<String> seq,
    Map<String, Set<String>> acts, {
    String? questId,
    int xpToComplete = kDefaultXpToCompleteObjective,
  }) => CourseLoOutline(
    courseId: courseId,
    questId: questId,
    orderedLoIds: seq,
    activityIdsByLo: acts,
    xpToComplete: xpToComplete,
  );

  /// Course A pins Mission m1 to a single activity; course B carries the same
  /// Mission with its own, different activity.
  List<CourseLoOutline> sharedMissionCourses() => [
    outline(
      'A',
      ['m1'],
      {
        'm1': {'a1'},
      },
    ),
    outline(
      'B',
      ['m1'],
      {
        'm1': {'b1'},
      },
    ),
  ];

  group('per-course scoping', () {
    test("a course's threshold is its OWN override, not another's", () {
      final r = resolveProgression(
        outlines: [
          outline(
            'A',
            ['m1'],
            {
              'm1': {'a1'},
            },
            xpToComplete: 200,
          ),
          outline(
            'B',
            ['m1'],
            {
              'm1': {'b1'},
            },
          ),
        ],
        xpByActivity: const {},
      );

      expect(r.forCourse('A')!.rollup['m1']!.threshold, 200);
      expect(r.forCourse('B')!.rollup['m1']!.threshold, 300);
    });

    test("a course does not credit another course's XP", () {
      final r = resolveProgression(
        outlines: sharedMissionCourses(),
        xpByActivity: const {'b1': 120},
      );

      expect(r.forCourse('A')!.rollup['m1']!.xp, 0);
      expect(r.forCourse('B')!.rollup['m1']!.xp, 120);
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
          ),
          outline(
            'B',
            ['m1'],
            {
              'm1': {'shared'},
            },
          ),
        ],
        xpByActivity: const {'shared': 80},
      );

      expect(r.forCourse('A')!.rollup['m1']!.xp, 80);
      expect(r.forCourse('B')!.rollup['m1']!.xp, 80);
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
            ),
            outline(
              'B',
              ['m1'],
              {
                'm1': {'b1'},
              },
            ),
          ],
          // Fully satisfies course B's m1; course A's m1 is untouched.
          xpByActivity: const {'b1': 300},
        );

        expect(r.forCourse('A')!.anchorMissionId, 'm1');
        expect(r.forCourse('B')!.rollup['m1']!.satisfied, isTrue);
      },
    );

    test('an unknown course resolves to no quest', () {
      final r = resolveProgression(
        outlines: sharedMissionCourses(),
        xpByActivity: const {},
      );

      expect(r.forCourse('never-joined'), isNull);
    });
  });

  group('questStars is scoped to its course', () {
    test("counts only the asking course's Missions", () {
      final r = resolveProgression(
        outlines: sharedMissionCourses(),
        xpByActivity: const {'b1': 300},
      );

      final a = r.questStars('A')!;
      expect(a.earned, 0);
      expect(a.total, 1);

      final b = r.questStars('B')!;
      expect(b.earned, 1);
      expect(b.total, 1);
    });

    test('an unresolved course is null, not an invented denominator', () {
      expect(ProgressionResolution.empty.questStars('A'), isNull);
    });
  });

  group('activity-less Missions (#7663)', () {
    /// TigToggle's report: a quest whose sequence carries five Missions but
    /// where only one has an activity. The panel renders that one Mission; the
    /// header used to count all five.
    ProgressionResolution oneRealMissionOfFive() => resolveProgression(
      outlines: [
        outline(
          'A',
          ['m1', 'm2', 'm3', 'm4', 'm5'],
          {
            'm1': {'a1'},
          },
        ),
      ],
      xpByActivity: const {},
    );

    test('do not inflate the quest denominator (one Mission of one)', () {
      final summary = oneRealMissionOfFive().questStars('A')!;
      expect(summary.total, 1);
      expect(summary.earned, 0);
    });

    test('are absent from the rollup, so the panel has nothing to render', () {
      final quest = oneRealMissionOfFive().forCourse('A')!;
      expect(quest.rollup.keys, ['m1']);
      expect(quest.rollup['m2'], isNull);
    });

    test('never become the anchor — there is nothing to play there', () {
      // m1 is unsatisfied, so it anchors. Once it IS satisfied, the quest is
      // done: the anchor must not fall through to an unplayable Mission, and
      // (#8997) must not fall back to the satisfied one either.
      final satisfied = resolveProgression(
        outlines: [
          outline(
            'A',
            ['m1', 'm2'],
            {
              'm1': {'a1'},
            },
          ),
        ],
        xpByActivity: const {'a1': 300},
      );
      expect(satisfied.forCourse('A')!.anchorMissionId, isNull);
    });

    test('a quest with no playable Mission has no anchor at all', () {
      final none = resolveProgression(
        outlines: [
          outline('A', ['m1', 'm2'], const {}),
        ],
        xpByActivity: const {},
      );
      expect(none.forCourse('A')!.anchorMissionId, isNull);
      expect(none.questStars('A')!.total, 0);
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
        xpByActivity: const {},
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
          ),
        ],
        xpByActivity: const {'a1': 300},
      );

      expect(r.missionGradient(['m1']), 0.0);
    });
  });

  group('two course rooms from one quest (#8087)', () {
    /// One quest ('q1') launched into two course rooms: room A pins Mission m1
    /// to its own activity, room B carries the same Mission with a different
    /// (side-quest) activity. Courses are keyed by room id; the shared quest
    /// uuid is the second key the band dedupes by.
    List<CourseLoOutline> twoRoomsOneQuest() => [
      outline(
        '!roomA:x',
        ['m1'],
        {
          'm1': {'a1'},
        },
        questId: 'q1',
      ),
      outline(
        '!roomB:x',
        ['m1'],
        {
          'm1': {'b1'},
        },
        questId: 'q1',
      ),
    ];

    test('each room resolves its own rollup — no last-room-wins collapse', () {
      final r = resolveProgression(
        outlines: twoRoomsOneQuest(),
        xpByActivity: const {'a1': 150},
      );

      expect(r.forCourse('!roomA:x')!.rollup['m1']!.xp, 150);
      expect(r.forCourse('!roomB:x')!.rollup['m1']!.xp, 0);
    });

    test("XP earned in one room's activity never credits the other", () {
      // The reported repro: earn in course B, course A displayed it.
      final r = resolveProgression(
        outlines: twoRoomsOneQuest(),
        xpByActivity: const {'b1': 300},
      );

      expect(r.forCourse('!roomA:x')!.rollup['m1']!.xp, 0);
      expect(r.questStars('!roomA:x')!.earned, 0);
      expect(r.forCourse('!roomB:x')!.rollup['m1']!.xp, 300);
      expect(r.questStars('!roomB:x')!.earned, 1);
    });

    test('the band counts the shared quest once, not once per room', () {
      final r = resolveProgression(
        outlines: twoRoomsOneQuest(),
        xpByActivity: const {},
      );

      expect(r.missionGradient(['m1']), 1.0);
    });

    test("a Mission satisfied in one room keeps the other room's signal", () {
      // Room A's m1 is satisfied (contribution 0); room B's differently-pinned
      // m1 is not. The quest's strongest per-room value stands (max, not
      // first-wins): the activity genuinely is the learner's next step in B.
      final r = resolveProgression(
        outlines: twoRoomsOneQuest(),
        xpByActivity: const {'a1': 300},
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
        xpByActivity: const {},
      );

      expect(r.missionGradient(['m1', 'm2']), 2.0);
    });
  });
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/quests/activity_family.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_completion_replay.dart';
import 'package:fluffychat/features/quests/mission_room_xp.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/saved_session_xp.dart';

/// When a Mission that was complete before its course's progress record
/// began first reached the threshold, replayed from history by the ring's
/// own rules (client#9643).
void main() {
  DateTime day(int d) => DateTime.utc(2026, 9, d, 12);

  const outline = CourseLoOutline(
    courseId: 'course',
    orderedLoIds: ['lo1'],
    activityIdsByLo: {
      'lo1': {'a1'},
    },
    lemmasByLo: {
      'lo1': {'casa'},
    },
    xpToComplete: 100,
  );

  OneConstructUse use(
    ConstructUseTypeEnum type,
    int xp,
    DateTime at, {
    String? roomId,
    String lemma = 'casa',
  }) => OneConstructUse(
    useType: type,
    lemma: lemma,
    constructType: ConstructTypeEnum.vocab,
    metadata: ConstructUseMetaData(roomId: roomId, timeStamp: at),
    category: 'NOUN',
    form: lemma,
    xp: xp,
  );

  SavedSessionXp session(String roomId, DateTime savedAt, {int goalXp = 0}) =>
      SavedSessionXp(
        activityId: 'a1',
        roomId: roomId,
        savedAt: savedAt,
        goalXp: goalXp,
      );

  DateTime? replay(List<OneConstructUse> uses, List<SavedSessionXp> sessions) =>
      MissionCompletionReplay(
        uses: uses,
        sessions: sessions,
      ).firstReached(outline, 'lo1');

  test('a session counts from when it was saved, not when it was played', () {
    expect(
      replay(
        [use(ConstructUseTypeEnum.wa, 80, day(1), roomId: 'r1')],
        [session('r1', day(3), goalXp: 50)],
      ),
      day(3),
    );
  });

  test('practice outside a session counts from when it was answered', () {
    expect(
      replay(
        [use(ConstructUseTypeEnum.corLM, 60, day(2))],
        [session('r1', day(1), goalXp: 50)],
      ),
      day(2),
    );
  });

  test('the first time it reached the threshold, even if it fell after', () {
    expect(
      replay([
        use(ConstructUseTypeEnum.corLM, 100, day(1)),
        use(ConstructUseTypeEnum.incLM, -10, day(2)),
      ], const []),
      day(1),
    );
  });

  test('a part below zero takes nothing from the others', () {
    expect(
      replay(
        [
          use(ConstructUseTypeEnum.wa, 100, day(1), roomId: 'r1'),
          use(ConstructUseTypeEnum.incLM, -30, day(1), roomId: 'r1'),
        ],
        [session('r1', day(2))],
      ),
      day(2),
    );
  });

  test('practice credited to a session after it was saved counts then', () {
    expect(
      replay(
        [
          use(ConstructUseTypeEnum.wa, 60, day(1), roomId: 'r1'),
          use(ConstructUseTypeEnum.corLM, 50, day(4), roomId: 'r1'),
        ],
        [session('r1', day(2))],
      ),
      day(4),
    );
  });

  test('a room that is not a saved session counts nothing', () {
    expect(
      replay([
        use(ConstructUseTypeEnum.wa, 500, day(1), roomId: 'unsaved'),
      ], const []),
      isNull,
    );
  });

  test('practice on a word off the Mission\'s list counts nothing', () {
    expect(
      replay([
        use(ConstructUseTypeEnum.corLM, 500, day(1), lemma: 'perro'),
      ], const []),
      isNull,
    );
  });

  test('a session of a copy of its activity counts toward it', () {
    const withCopy = CourseLoOutline(
      courseId: 'course',
      orderedLoIds: ['lo1'],
      activityIdsByLo: {
        'lo1': {'a1'},
      },
      xpToComplete: 100,
      credit: CourseCredit(
        family: {'a1': 'a1', 'a1-copy': 'a1'},
        shownIds: {'a1'},
      ),
    );
    final replay = MissionCompletionReplay(
      uses: [use(ConstructUseTypeEnum.wa, 100, day(1), roomId: 'r1')],
      sessions: [
        SavedSessionXp(
          activityId: 'a1-copy',
          roomId: 'r1',
          savedAt: day(2),
          goalXp: 0,
        ),
      ],
    );
    expect(replay.firstReached(withCopy, 'lo1'), day(2));
  });

  test('a session of another Mission\'s activity counts nothing', () {
    final replay = MissionCompletionReplay(
      uses: [use(ConstructUseTypeEnum.wa, 100, day(1), roomId: 'r1')],
      sessions: [
        SavedSessionXp(
          activityId: 'b1',
          roomId: 'r1',
          savedAt: day(2),
          goalXp: 50,
        ),
      ],
    );
    expect(replay.firstReached(outline, 'lo1'), isNull);
  });

  group('agrees with the ring\'s own count at every moment', () {
    const lemmas = ['casa', 'perro', 'viaje', 'gato'];
    const activities = ['a1', 'a2', 'a1-copy', 'b1', 'c9'];
    const types = [
      ConstructUseTypeEnum.wa,
      ConstructUseTypeEnum.incIGC,
      ConstructUseTypeEnum.pvm,
      ConstructUseTypeEnum.corLM,
      ConstructUseTypeEnum.incLM,
    ];

    CourseLoOutline course(
      int xpToComplete, {
      required bool withCopy,
      required bool sharedWord,
    }) => CourseLoOutline(
      courseId: 'course',
      orderedLoIds: const ['lo1', 'lo2'],
      activityIdsByLo: const {
        'lo1': {'a1', 'a2'},
        'lo2': {'b1'},
      },
      // A word two Missions share counts toward both.
      lemmasByLo: {
        'lo1': const {'casa', 'perro'},
        'lo2': {'viaje', if (sharedWord) 'casa'},
      },
      xpToComplete: xpToComplete,
      credit: withCopy
          ? const CourseCredit(
              family: {'a1': 'a1', 'a1-copy': 'a1', 'a2': 'a2', 'b1': 'b1'},
              shownIds: {'a1', 'a2', 'b1'},
            )
          : CourseCredit.none,
    );

    /// The ring's count at [moment], by the resolver, over what existed then.
    int ringXpAt(
      DateTime moment,
      CourseLoOutline outline,
      List<OneConstructUse> uses,
      List<SavedSessionXp> sessions,
      String missionId,
    ) {
      final usesThen = [
        for (final use in uses)
          if (!use.timeStamp.isAfter(moment)) use,
      ];
      final credited = MissionRoomXp.of(usesThen).credited;
      return resolveProgression(
        outlines: [outline],
        xpByActivity: sumXpByActivity([
          for (final s in sessions)
            if (!s.savedAt.isAfter(moment))
              (
                activityId: s.activityId,
                xp: (credited[s.roomId] ?? 0) + s.goalXp,
              ),
        ]),
        practiceXpByLemma: MissionXpCache.practiceXpByLemmaOf(usesThen),
      ).quests.first.rollup[missionId]!.xp;
    }

    for (var seed = 0; seed < 200; seed++) {
      test('history $seed', () {
        final random = Random(seed);
        DateTime at() => DateTime.utc(2026, 9, 1 + random.nextInt(20));
        final sessionCount = 1 + random.nextInt(6);
        final sessions = [
          for (var i = 0; i < sessionCount; i++)
            SavedSessionXp(
              activityId: activities[random.nextInt(activities.length)],
              roomId: 'r$i',
              savedAt: at(),
              goalXp: kGoalXp * random.nextInt(2),
            ),
        ];
        final rooms = [for (final s in sessions) s.roomId, null, 'unsaved'];
        // Scores around zero, so running sums often dip below it: where the
        // floors decide the answer.
        final useCount = random.nextInt(80);
        final uses = [
          for (var i = 0; i < useCount; i++)
            use(
              types[random.nextInt(types.length)],
              random.nextInt(31) - 15,
              at(),
              roomId: rooms[random.nextInt(rooms.length)],
              lemma: lemmas[random.nextInt(lemmas.length)],
            ),
        ];
        final outline = course(
          10 + random.nextInt(120),
          withCopy: random.nextBool(),
          sharedWord: random.nextBool(),
        );
        final moments = {
          for (final s in sessions) s.savedAt,
          for (final u in uses) u.timeStamp,
        }.toList()..sort();
        final replay = MissionCompletionReplay(uses: uses, sessions: sessions);
        for (final missionId in outline.orderedLoIds) {
          final expected = moments
              .where(
                (m) =>
                    ringXpAt(m, outline, uses, sessions, missionId) >=
                    outline.xpToComplete,
              )
              .firstOrNull;
          expect(
            replay.firstReached(outline, missionId),
            expected,
            reason: missionId,
          );
        }
      });
    }
  });

  test('a Mission that never reached the threshold has no date', () {
    expect(
      replay(
        [use(ConstructUseTypeEnum.corLM, 40, day(1))],
        [session('r1', day(2), goalXp: 50)],
      ),
      isNull,
    );
  });
}

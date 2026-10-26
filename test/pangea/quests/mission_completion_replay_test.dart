import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/quests/activity_family.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_completion_replay.dart';
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

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';

/// Practice outside any session counts toward every Mission whose word list
/// holds the practised word, whether or not the learner ever wrote it in a
/// session (#9420 prototype).
void main() {
  CourseLoOutline outline({int xpToComplete = 100}) => CourseLoOutline(
    courseId: 'course',
    orderedLoIds: const ['lo-1', 'lo-2'],
    activityIdsByLo: const {
      'lo-1': {'a1'},
      'lo-2': {'b1'},
    },
    lemmasByLo: const {
      'lo-1': {'familia', 'casa'},
      'lo-2': {'familia', 'viaje'},
    },
    xpToComplete: xpToComplete,
  );

  test('sums the practice XP on the given words only', () {
    expect(
      MissionXpBreakdown.practiceFor(
        {'familia', 'casa'},
        {'familia': 10, 'casa': 5, 'perro': 50},
      ),
      15,
    );
    expect(MissionXpBreakdown.practiceFor(const {}, {'familia': 10}), 0);
  });

  test('a Mission adds word-list practice to its activity XP', () {
    final quest = resolveProgression(
      outlines: [outline()],
      xpByActivity: const {'a1': 30},
      practiceXpByLemma: const {'casa': 5, 'viaje': 7},
    ).forCourse('course')!;
    expect(quest.rollup['lo-1']!.xp, 35);
    expect(quest.rollup['lo-2']!.xp, 7);
  });

  test('a word on two Missions\' lists counts toward both', () {
    final quest = resolveProgression(
      outlines: [outline()],
      xpByActivity: const {},
      practiceXpByLemma: const {'familia': 10},
    ).forCourse('course')!;
    expect(quest.rollup['lo-1']!.xp, 10);
    expect(quest.rollup['lo-2']!.xp, 10);
  });

  test('word-list practice alone can complete a Mission and move the '
      'anchor', () {
    final quest = resolveProgression(
      outlines: [outline(xpToComplete: 20)],
      xpByActivity: const {},
      practiceXpByLemma: const {'casa': 20},
    ).forCourse('course')!;
    expect(quest.rollup['lo-1']!.satisfied, isTrue);
    expect(quest.anchorMissionId, 'lo-2');
  });

  test('conversation is chat, speaking and goals; practice stands apart '
      '(#9559)', () {
    const xp = MissionXpBreakdown(
      chat: 120,
      speaking: 80,
      goals: 200,
      practice: 50,
    );
    expect(xp.conversation, 400);
    expect(xp.total, xp.conversation + xp.practice);
  });

  test('the cache publishes room-less practice by word', () {
    final cache = MissionXpCache.instance;
    addTearDown(() => cache.seed());
    cache.seed(xpByRoom: {'r1': 40}, practiceXpByLemma: {'familia': 10});
    expect(cache.creditedXpByRoom, {'r1': 40});
    expect(cache.practiceXpByLemma, {'familia': 10});
  });
}

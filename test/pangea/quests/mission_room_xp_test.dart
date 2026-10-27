import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/quests/mission_room_xp.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';

/// Each part of a session — chat, speaking, practice — counts as zero when it
/// nets below zero in its room, so wrong answers in one part never take XP
/// earned in another (client#9643).
void main() {
  OneConstructUse use(
    ConstructUseTypeEnum type,
    int xp, {
    String? roomId = 'r1',
    String lemma = 'casa',
  }) => OneConstructUse(
    useType: type,
    lemma: lemma,
    constructType: ConstructTypeEnum.vocab,
    metadata: ConstructUseMetaData(
      roomId: roomId,
      timeStamp: DateTime(2026, 10, 26),
    ),
    category: 'NOUN',
    form: lemma,
    xp: xp,
  );

  test('a part that nets below zero counts as zero, the others stand', () {
    final xp = MissionRoomXp.of([
      use(ConstructUseTypeEnum.wa, 40),
      use(ConstructUseTypeEnum.pvm, 20),
      use(ConstructUseTypeEnum.corLM, 5),
      use(ConstructUseTypeEnum.incLM, -10),
      use(ConstructUseTypeEnum.incLM, -5),
    ]);
    expect(xp.chat, {'r1': 40});
    expect(xp.speaking, {'r1': 20});
    expect(xp.practice, isEmpty);
  });

  test('a part that nets to exactly zero counts nothing', () {
    final xp = MissionRoomXp.of([
      use(ConstructUseTypeEnum.wa, 3),
      use(ConstructUseTypeEnum.incIGC, -3),
    ]);
    expect(xp.chat, isEmpty);
  });

  test('a positive part keeps its wrong answers', () {
    final xp = MissionRoomXp.of([
      use(ConstructUseTypeEnum.corLM, 10),
      use(ConstructUseTypeEnum.incLM, -4),
    ]);
    expect(xp.practice, {'r1': 6});
  });

  test('each room is floored on its own', () {
    final xp = MissionRoomXp.of([
      use(ConstructUseTypeEnum.incLM, -10, roomId: 'r1'),
      use(ConstructUseTypeEnum.corLM, 10, roomId: 'r2'),
    ]);
    expect(xp.practice, {'r2': 10});
  });

  test('a floored part leaves the skills, so they still add up', () {
    final xp = MissionRoomXp.of([
      use(ConstructUseTypeEnum.wa, 40),
      use(ConstructUseTypeEnum.incLM, -10),
    ]);
    final skills = xp.skills['r1']!;
    expect(skills.values.fold<int>(0, (a, b) => a + b), 40);
    expect(skills[LearningSkillsEnum.writing], 40);
  });

  test('uses outside any room are not in-room XP', () {
    final xp = MissionRoomXp.of([
      use(ConstructUseTypeEnum.corLM, 10, roomId: null),
    ]);
    expect(xp.practice, isEmpty);
    expect(xp.skills, isEmpty);
  });
}

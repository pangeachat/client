import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';

void main() {
  // #8083: QuestRepo.outline must cache successes only. A cached error pins a
  // transient failure (or a since-restored quest) for the process lifetime,
  // which defeats the world map's empty-cache self-heal retry — the retry
  // replays the stale error forever instead of recovering.
  group('QuestRepo.outline error caching', () {
    const quest = QuestPlan(
      id: 'quest-1',
      name: 'Quest',
      description: '',
      targetLanguage: 'es',
      sequence: [],
    );

    var buildCalls = 0;

    setUp(() {
      buildCalls = 0;
      QuestRepo.resetOutlineCacheForTest();
    });

    tearDown(() {
      QuestRepo.debugBuildOutline = null;
      QuestRepo.resetOutlineCacheForTest();
    });

    test('an error result is not cached — the next call retries', () async {
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
        buildCalls++;
        return Result.error(MissingQuestException());
      };

      final first = await QuestRepo.outline('quest-1');
      expect(first.isError, isTrue);
      final second = await QuestRepo.outline('quest-1');
      expect(second.isError, isTrue);

      expect(buildCalls, 2);
    });

    test('a retry after an error can succeed and then caches', () async {
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
        buildCalls++;
        if (buildCalls == 1) return Result.error(MissingQuestException());
        return Result.value(const QuestOutline(quest: quest, groups: []));
      };

      expect((await QuestRepo.outline('quest-1')).isError, isTrue);
      expect((await QuestRepo.outline('quest-1')).isValue, isTrue);
      // The success is now cached — no further build.
      expect((await QuestRepo.outline('quest-1')).isValue, isTrue);
      expect(buildCalls, 2);
    });

    test('a success is cached per (quest id, course room)', () async {
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
        buildCalls++;
        return Result.value(const QuestOutline(quest: quest, groups: []));
      };

      await QuestRepo.outline('quest-1');
      await QuestRepo.outline('quest-1');
      expect(buildCalls, 1);

      // A course-member read must not share the plain read's cache row.
      await QuestRepo.outline('quest-1', courseRoomId: '!room:server');
      expect(buildCalls, 2);
    });

    test('concurrent calls share one in-flight build, even on error', () async {
      final gate = Completer<Result<QuestOutline>>();
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) {
        buildCalls++;
        return gate.future;
      };

      final first = QuestRepo.outline('quest-1');
      final second = QuestRepo.outline('quest-1');
      gate.complete(Result.error(MissingQuestException()));

      expect((await first).isError, isTrue);
      expect((await second).isError, isTrue);
      expect(buildCalls, 1);

      // The shared error was not cached — a later call retries.
      await QuestRepo.outline('quest-1');
      expect(buildCalls, 2);
    });
  });
}

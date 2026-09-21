import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';

void main() {
  // #8083: QuestRepo.outline must not cache TRANSIENT errors. A cached
  // transient failure pins it for the process lifetime, which defeats the world
  // map's empty-cache self-heal retry — the retry replays the stale error
  // forever instead of recovering.
  //
  // #8358: a confirmed 404 (MissingQuestException) is the exception. It is a
  // statement about the resource, not a failure to reach it, so it IS cached —
  // otherwise an old course room referencing a removed quest re-requests it for
  // the life of the process.
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
      QuestRepo.debugDisplayL1 = null;
      QuestRepo.resetOutlineCacheForTest();
    });

    test('a transient error is not cached — the next call retries', () async {
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
        buildCalls++;
        return Result.error(Exception('timeout'));
      };

      final first = await QuestRepo.outline('quest-1');
      expect(first.isError, isTrue);
      final second = await QuestRepo.outline('quest-1');
      expect(second.isError, isTrue);

      expect(buildCalls, 2);
    });

    test(
      'a retry after a transient error can succeed and then caches',
      () async {
        QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
          buildCalls++;
          if (buildCalls == 1) return Result.error(Exception('timeout'));
          return Result.value(const QuestOutline(quest: quest, groups: []));
        };

        expect((await QuestRepo.outline('quest-1')).isError, isTrue);
        expect((await QuestRepo.outline('quest-1')).isValue, isTrue);
        // The success is now cached — no further build.
        expect((await QuestRepo.outline('quest-1')).isValue, isTrue);
        expect(buildCalls, 2);
      },
    );

    test('a confirmed 404 is cached — later calls do not refetch', () async {
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
        buildCalls++;
        return Result.error(MissingQuestException());
      };

      final first = await QuestRepo.outline('quest-1');
      final second = await QuestRepo.outline('quest-1');
      await QuestRepo.outline('quest-1');

      expect(first.asError!.error, isA<MissingQuestException>());
      // The memoized result is the same error, so callers keep rendering the
      // known-missing state rather than a different failure.
      expect(second.asError!.error, isA<MissingQuestException>());
      expect(buildCalls, 1);
    });

    test('a cached 404 is scoped to its (quest id, course room) row', () async {
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
        buildCalls++;
        return Result.error(MissingQuestException());
      };

      await QuestRepo.outline('quest-1');
      await QuestRepo.outline('quest-1', courseRoomId: '!room:server');
      await QuestRepo.outline('quest-2');

      expect(buildCalls, 3);
    });

    test('forceRefresh recovers a restored quest past a cached 404', () async {
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
        buildCalls++;
        if (buildCalls == 1) return Result.error(MissingQuestException());
        return Result.value(const QuestOutline(quest: quest, groups: []));
      };

      expect((await QuestRepo.outline('quest-1')).isError, isTrue);
      expect(
        (await QuestRepo.outline('quest-1', forceRefresh: true)).isValue,
        isTrue,
      );
      // The success replaced the cached 404 — no further build.
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

    test('a cached outline is scoped to its display language', () async {
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
        buildCalls++;
        return Result.value(const QuestOutline(quest: quest, groups: []));
      };

      QuestRepo.debugDisplayL1 = 'fr';
      await QuestRepo.outline('quest-1');
      await QuestRepo.outline('quest-1');
      expect(buildCalls, 1);

      // #8577: activity-card text follows the display language, so flipping
      // the "app in target language" toggle must miss the 'fr' row and
      // refetch rather than replay the other language...
      QuestRepo.debugDisplayL1 = 'de';
      await QuestRepo.outline('quest-1');
      expect(buildCalls, 2);

      // ...while flipping back reuses the already-cached row.
      QuestRepo.debugDisplayL1 = 'fr';
      await QuestRepo.outline('quest-1');
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
      gate.complete(Result.error(Exception('timeout')));

      expect((await first).isError, isTrue);
      expect((await second).isError, isTrue);
      expect(buildCalls, 1);

      // The shared transient error was not cached — a later call retries.
      await QuestRepo.outline('quest-1');
      expect(buildCalls, 2);
    });
  });
}

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/world/world_map_pins_manager.dart';
import '../courses/course_missions_fixtures.dart';
import '../get_test_client.dart';

void main() {
  // #8083: the empty-cache self-heal used to re-fire on every rate-limited
  // sync for a learner whose joined courses are all unresolvable (e.g.
  // orphaned quest plans), refetching and re-logging in a loop. The pure rule
  // paces that retry by kEmptyObjectiveCacheRetryCooldown while leaving
  // set-change rebuilds (course join/leave) immediate.
  group('shouldRebuildObjectiveCacheNow', () {
    final now = DateTime(2026, 8, 3, 12);

    test('never rebuilds while a rebuild is in flight', () {
      expect(
        shouldRebuildObjectiveCacheNow(
          rebuilding: true,
          setChanged: true,
          emptyButHasCourses: true,
          lastRebuildAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('a set change rebuilds immediately, cooldown or not', () {
      expect(
        shouldRebuildObjectiveCacheNow(
          rebuilding: false,
          setChanged: true,
          emptyButHasCourses: false,
          lastRebuildAt: now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        isTrue,
      );
    });

    test('a populated, unchanged cache does not rebuild', () {
      expect(
        shouldRebuildObjectiveCacheNow(
          rebuilding: false,
          setChanged: false,
          emptyButHasCourses: false,
          lastRebuildAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('the empty-cache retry is due when no rebuild has run', () {
      expect(
        shouldRebuildObjectiveCacheNow(
          rebuilding: false,
          setChanged: false,
          emptyButHasCourses: true,
          lastRebuildAt: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('the empty-cache retry waits out the cooldown', () {
      expect(
        shouldRebuildObjectiveCacheNow(
          rebuilding: false,
          setChanged: false,
          emptyButHasCourses: true,
          lastRebuildAt: now.subtract(
            kEmptyObjectiveCacheRetryCooldown - const Duration(seconds: 1),
          ),
          now: now,
        ),
        isFalse,
      );
    });

    test('the empty-cache retry fires once the cooldown has passed', () {
      expect(
        shouldRebuildObjectiveCacheNow(
          rebuilding: false,
          setChanged: false,
          emptyButHasCourses: true,
          lastRebuildAt: now.subtract(kEmptyObjectiveCacheRetryCooldown),
          now: now,
        ),
        isTrue,
      );
    });
  });

  /// Content Studio — the world map rebuilds its joined-course outlines when a
  /// course's own copy changes revision, not only when the joined set does.
  group('a course copy revision change counts as a change', () {
    late Client client;

    setUp(() async {
      client = await getTestClient();
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async => Result.value(
        const QuestOutline(
          quest: QuestPlan(
            id: 'quest-1',
            name: '',
            description: '',
            targetLanguage: 'es',
            sequence: [],
          ),
          groups: [],
        ),
      );
    });
    tearDown(() async {
      QuestRepo.debugBuildOutline = null;
      QuestRepo.resetOutlineCacheForTest();
      await client.dispose();
    });

    test('rebuilds once per new revision', () async {
      final room = Room(
        id: '!course:fakeServer.notExisting',
        client: client,
        membership: Membership.join,
      );
      putState(room, EventTypes.RoomCreate, {'type': RoomCreationTypes.mSpace});
      putPowerLevels(room);
      putState(
        room,
        PangeaEventTypes.coursePlan,
        CoursePlanEvent(uuid: 'quest-1', l2: 'es').toJson(),
      );
      client.rooms.add(room);

      final manager = WorldMapPinsManager();
      await manager.rebuildObjectiveCache(client);
      // The empty outline leaves the cache empty, but the retry cooldown has
      // just started, so only a revision change can ask for a rebuild here.
      expect(
        manager.shouldRebuildObjectiveCache(client),
        isFalse,
        reason: 'unchanged',
      );

      putCopy(room, {'lo-1': []}, revision: 2);
      expect(manager.shouldRebuildObjectiveCache(client), isTrue);

      await manager.rebuildObjectiveCache(client);
      expect(manager.shouldRebuildObjectiveCache(client), isFalse);
    });
  });
}

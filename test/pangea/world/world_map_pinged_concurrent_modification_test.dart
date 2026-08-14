import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/world/world_map_pins_manager.dart';
import '../get_test_client.dart';

/// #8361 (Sentry CLIENT-DBW) — `recomputePinged` awaits `getTimeline()` once per
/// course space, and the SDK's sync handler mutates `client.rooms` **in place**
/// across those awaits (`rooms.insert` on a join, `rooms.removeAt` on a leave —
/// `Client._handleRooms`). Iterating a lazy `client.rooms.where(...)` view over
/// that list therefore threw `Concurrent modification during iteration`, aborting
/// the scan partway and leaving pinged pins stale until the next clean pass.
///
/// The room list moving mid-scan is correct SDK behaviour and not something the
/// map may block, so the scan reads a snapshot — these tests drive exactly the
/// two mutations the sync path performs and assert the scan still completes.
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Event stateEvent(
    Room room, {
    required String type,
    required Map<String, dynamic> content,
    String stateKey = '',
  }) => Event(
    type: type,
    content: content,
    stateKey: stateKey,
    senderId: userId,
    eventId: '\$${type}_${room.id}_$stateKey',
    originServerTs: DateTime.utc(2026, 1, 1),
    room: room,
  );

  /// A joined course space — a space carrying a course plan, which is exactly
  /// what the pinged scan selects out of `client.rooms`.
  Room courseSpace(String id) {
    final space = Room(id: id, client: client, membership: Membership.join);
    space.setState(
      stateEvent(
        space,
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
      ),
    );
    space.setState(
      stateEvent(
        space,
        type: PangeaEventTypes.coursePlan,
        content: CoursePlanEvent(uuid: 'quest-$id', l2: 'de').toJson(),
      ),
    );
    client.rooms.add(space);
    return space;
  }

  /// Several spaces, so the scan suspends on a `getTimeline()` await with more
  /// of the collection still to walk — the window the sync handler writes into.
  void seedCourseSpaces() {
    for (var i = 0; i < 3; i++) {
      courseSpace('!course$i:fakeServer.notExisting');
    }
  }

  group('recomputePinged survives client.rooms moving mid-scan', () {
    test(
      'a course joined during the scan (the SDK sync-path rooms.insert)',
      () {
        seedCourseSpaces();
        final manager = WorldMapPinsManager();

        // Not awaited: the scan is now suspended on its first getTimeline().
        final scan = manager.recomputePinged(client);
        courseSpace('!joinedMidScan:fakeServer.notExisting');

        expect(scan, completes);
      },
    );

    test(
      'a course left during the scan (the SDK sync-path rooms.removeAt)',
      () {
        seedCourseSpaces();
        final manager = WorldMapPinsManager();

        final scan = manager.recomputePinged(client);
        client.rooms.removeLast();

        expect(scan, completes);
      },
    );

    test('a non-course room arriving during the scan — the list it walks is '
        'the whole of client.rooms, so any room update is a mutation', () {
      seedCourseSpaces();
      final manager = WorldMapPinsManager();

      final scan = manager.recomputePinged(client);
      client.rooms.add(
        Room(
          id: '!chat:fakeServer.notExisting',
          client: client,
          membership: Membership.join,
        ),
      );

      expect(scan, completes);
    });
  });
}

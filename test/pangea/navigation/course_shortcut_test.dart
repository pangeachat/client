import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/course_shortcut.dart';
import '../get_test_client.dart';

/// The narrow rail's course-shortcut slot (#8599): which course it shows once
/// the remembered one is gone, and — just as importantly — that it notices at
/// all without waiting for a route change. See "Single-column bottom nav" in
/// routing.instructions.md.
void main() {
  late Client client;

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Room space(String localpart, {Membership membership = Membership.join}) {
    final room = Room(
      id: '!$localpart:fakeServer.notExisting',
      client: client,
      membership: membership,
    );
    room.setState(
      Event(
        type: EventTypes.RoomCreate,
        content: {'type': 'm.space'},
        senderId: '@test:fakeServer.notExisting',
        stateKey: '',
        eventId: '\$create-$localpart',
        originServerTs: DateTime.utc(2026, 1, 1),
        room: room,
      ),
    );
    return room;
  }

  void rename(Room room, String name) => room.setState(
    Event(
      type: EventTypes.RoomName,
      content: {'name': name},
      senderId: '@test:fakeServer.notExisting',
      stateKey: '',
      eventId: '\$name-$name',
      originServerTs: DateTime.utc(2026, 1, 2),
      room: room,
    ),
  );

  /// A sync that carries a room update but changes no membership — the shape
  /// of ordinary traffic (a message, a read receipt).
  SyncUpdate chatter() => SyncUpdate(
    nextBatch: 'batch',
    rooms: RoomsUpdate(
      join: {'!chat:fakeServer.notExisting': JoinedRoomUpdate()},
    ),
  );

  /// Drive one sync through the client and let the shortcut's throttled
  /// listener run. The throttle is leading-edge, so the first event lands
  /// immediately; the extra slice covers the trailing re-fire.
  Future<void> pump(SyncUpdate update) async {
    client.onSync.add(update);
    await Future.delayed(const Duration(milliseconds: 1100));
  }

  test('shows nothing when no course is joined — the `+` button', () {
    client.rooms = [];
    expect(CourseShortcut(client).course, isNull);
  });

  test('shows the single joined course', () {
    final a = space('a');
    client.rooms = [a];
    expect(CourseShortcut(client).course?.id, a.id);
  });

  test('shows the most-recently-opened course, not the client order', () {
    final a = space('a');
    final b = space('b');
    // `b` leads the client's own recency order, so only the opened-memory can
    // produce `a` — otherwise this passes on the fallback by coincidence.
    client.rooms = [b, a];
    final shortcut = CourseShortcut(client)
      ..opened(b.id)
      ..opened(a.id);
    expect(shortcut.course?.id, a.id);
  });

  test(
    'rebuilds the slot when a course is deleted, without a route change',
    () async {
      final a = space('a');
      final other = space('other');
      final doomed = space('doomed');
      // `other` outranks `a` in the client's own order, so landing on `a` can
      // only come from the opened-memory, never from the fallback.
      client.rooms = [doomed, other, a];
      final shortcut = CourseShortcut(client)
        ..opened(a.id)
        ..opened(doomed.id);
      expect(shortcut.course?.id, doomed.id);

      var notified = 0;
      shortcut.addListener(() => notified++);

      // The course is gone from the client, as it is after the delete's sync.
      client.rooms = [other, a];
      await pump(
        SyncUpdate(
          nextBatch: 'batch',
          rooms: RoomsUpdate(join: {doomed.id: JoinedRoomUpdate()}),
        ),
      );

      expect(notified, 1, reason: 'the slot must be told the course went away');
      // The course opened BEFORE the deleted one — not an arbitrary other one.
      expect(shortcut.course?.id, a.id);
    },
  );

  test('leaving the slotted course falls back the same way', () async {
    final a = space('a');
    final other = space('other');
    final left = space('left');
    client.rooms = [left, other, a];
    final shortcut = CourseShortcut(client)
      ..opened(a.id)
      ..opened(left.id);

    client.rooms = [other, a, space('left', membership: Membership.leave)];
    await pump(chatter());

    expect(shortcut.course?.id, a.id);
  });

  test('ordinary traffic does not rebuild the slot', () async {
    client.rooms = [space('a'), space('b')];
    final shortcut = CourseShortcut(client);
    var notified = 0;
    shortcut.addListener(() => notified++);

    for (var i = 0; i < 3; i++) {
      await pump(chatter());
    }

    expect(
      notified,
      0,
      reason:
          'the nav layer rebuilds its whole subtree — including the open '
          'panel in the cavity — on every notification',
    );
  });

  test('a course joined mid-session rebuilds the slot', () async {
    final a = space('a');
    client.rooms = [a];
    final shortcut = CourseShortcut(client);
    var notified = 0;
    shortcut.addListener(() => notified++);

    final joined = space('new');
    client.rooms = [joined, a];
    await pump(
      SyncUpdate(
        nextBatch: 'batch',
        rooms: RoomsUpdate(join: {joined.id: JoinedRoomUpdate()}),
      ),
    );

    expect(notified, 1);
  });

  test(
    'a renamed course rebuilds the slot — the slot draws its name',
    () async {
      final a = space('a');
      client.rooms = [a];
      final shortcut = CourseShortcut(client);
      var notified = 0;
      shortcut.addListener(() => notified++);

      rename(a, 'Renamed');
      await pump(chatter());

      expect(notified, 1);
    },
  );

  test(
    'one shared instance per client, a fresh one on account switch',
    () async {
      final first = courseShortcutFor(client);
      expect(identical(courseShortcutFor(client), first), isTrue);

      final other = await getTestClient();
      addTearDown(other.dispose);
      expect(identical(courseShortcutFor(other), first), isFalse);
    },
  );
}

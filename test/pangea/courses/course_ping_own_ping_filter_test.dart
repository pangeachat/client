import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/activity_sessions/course_ping_constants.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_extension.dart';
import '../get_test_client.dart';

/// #8610 — a learner's own course ping must not notify them. Every ping
/// notifier (nav-rail bell, course-tile bell, and the CoursePingBadgeCache
/// behind the course-plan badges) reads through [unreadCoursePingEvent], so
/// the sender filter there is what keeps a host's own ping from badging their
/// own surfaces while a coursemate's ping still does.
void main() {
  sqfliteFfiInit();

  late Client client;

  // sqflite's ':memory:' database is shared process-wide, so rows outlive a
  // client. Fresh room/event ids per test keep handleSync from deduping
  // against an earlier test's copy.
  var testCounter = 0;

  setUp(() async {
    client = await getTestClient();
    FakeMatrixApi.client = client;
    testCounter++;
  });
  tearDown(() async {
    await client.dispose();
  });

  MatrixEvent ping({
    required String senderId,
    required String eventId,
    required DateTime ts,
  }) => MatrixEvent(
    eventId: eventId,
    type: EventTypes.Message,
    content: {
      'msgtype': MessageTypes.Text,
      'body': 'join my activity!',
      CoursePingConstants.coursePingRoomId: '!session:example.com',
      CoursePingConstants.coursePingActivityId: 'activity-1',
    },
    senderId: senderId,
    originServerTs: ts,
  );

  /// Builds a joined room through a sync so it has a real timeline.
  Future<Room> syncRoomWithPings(List<MatrixEvent> events) async {
    final roomId = '!course$testCounter:example.com';
    await client.handleSync(
      SyncUpdate(
        nextBatch: 'batch$testCounter',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(
              timeline: TimelineUpdate(prevBatch: 'prev1', events: events),
            ),
          },
        ),
      ),
    );
    return client.getRoomById(roomId)!;
  }

  group('unreadCoursePingEvent sender filter (#8610)', () {
    test('the sender\'s own ping does not notify them', () async {
      final room = await syncRoomWithPings([
        ping(
          senderId: client.userID!,
          eventId: '\$own$testCounter:example.com',
          ts: DateTime.utc(2026, 1, 2),
        ),
      ]);

      expect(await room.unreadCoursePingEvent, isNull);
    });

    test('a coursemate\'s ping still notifies', () async {
      final room = await syncRoomWithPings([
        ping(
          senderId: '@other:example.com',
          eventId: '\$other$testCounter:example.com',
          ts: DateTime.utc(2026, 1, 2),
        ),
      ]);

      final event = await room.unreadCoursePingEvent;
      expect(event?.senderId, '@other:example.com');
    });

    test('an own ping newer than a coursemate\'s does not mask it', () async {
      final otherEventId = '\$other$testCounter:example.com';
      final room = await syncRoomWithPings([
        ping(
          senderId: '@other:example.com',
          eventId: otherEventId,
          ts: DateTime.utc(2026, 1, 1),
        ),
        ping(
          senderId: client.userID!,
          eventId: '\$own$testCounter:example.com',
          ts: DateTime.utc(2026, 1, 2),
        ),
      ]);

      final event = await room.unreadCoursePingEvent;
      expect(event?.eventId, otherEventId);
    });
  });
}

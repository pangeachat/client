import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'get_test_client.dart';

/// #8636 — call speech anchors its construct uses to non-message events (the
/// pangea.call card, or on the answering side the ring notification), and the
/// example-message displays were wrapping those in PangeaMessageEvent, which
/// only holds m.room.message. The lookup now returns null for any non-message
/// anchor instead of building a wrapper the constructor itself reports as
/// invalid.
void main() {
  sqfliteFfiInit();

  late Client client;

  // sqflite's ':memory:' database is shared process-wide, so rows outlive a
  // client. Fresh room/event ids per test keep handleSync from deduping
  // against a previous test's rows.
  var testCounter = 0;

  setUp(() async {
    testCounter++;
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  /// Builds a joined room through a sync so its events are readable, then
  /// looks up a use anchored to [eventId]. The lookup waits for a sync when
  /// the client has never completed one, and only the real sync loop records
  /// that — so the no-op handleSync below releases the wait either way.
  Future<PangeaMessageEvent?> lookUp(
    String roomId,
    String eventId,
    List<MatrixEvent> events,
  ) async {
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

    final use = OneConstructUse(
      useType: ConstructUseTypeEnum.pvc,
      lemma: 'hola',
      form: 'hola',
      constructType: ConstructTypeEnum.vocab,
      category: 'INTJ',
      xp: ConstructUseTypeEnum.pvc.pointValue,
      metadata: ConstructUseMetaData(
        roomId: roomId,
        eventId: eventId,
        timeStamp: DateTime.utc(2026, 1, 2),
      ),
    );

    final future = client.getEventByConstructUse(use);
    await client.handleSync(SyncUpdate(nextBatch: 'nudge$testCounter'));
    return future;
  }

  test('a use anchored to a pangea.call card resolves to no message', () async {
    final eventId = '\$call$testCounter:example.com';
    final result = await lookUp('!room$testCounter:example.com', eventId, [
      MatrixEvent(
        eventId: eventId,
        type: PangeaEventTypes.call,
        senderId: '@caller:example.com',
        originServerTs: DateTime.utc(2026, 1, 2),
        content: {
          'msgtype': PangeaEventTypes.call,
          'body': 'Voice call (2:34)',
          'duration_ms': 154000,
          'video': false,
          'answered': true,
          'declined': false,
        },
      ),
    ]);
    expect(result, isNull);
  });

  test(
    'a use anchored to a ring notification resolves to no message',
    () async {
      final eventId = '\$ring$testCounter:example.com';
      final result = await lookUp('!room$testCounter:example.com', eventId, [
        MatrixEvent(
          eventId: eventId,
          type: PangeaEventTypes.callNotification,
          senderId: '@caller:example.com',
          originServerTs: DateTime.utc(2026, 1, 2),
          content: {
            'application': {'type': 'm.call', 'notification_type': 'ring'},
            'm.text': [
              {'body': 'Incoming call'},
            ],
          },
        ),
      ]);
      expect(result, isNull);
    },
  );

  test('a use anchored to a message still resolves to it', () async {
    final eventId = '\$msg$testCounter:example.com';
    final result = await lookUp('!room$testCounter:example.com', eventId, [
      MatrixEvent(
        eventId: eventId,
        type: EventTypes.Message,
        senderId: '@caller:example.com',
        originServerTs: DateTime.utc(2026, 1, 2),
        content: {'msgtype': MessageTypes.Text, 'body': 'hola'},
      ),
    ]);
    expect(result?.eventId, eventId);
  });
}

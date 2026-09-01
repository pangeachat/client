import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/extensions/pangea_event_extension.dart';
import 'get_test_client.dart';

/// [PangeaEvent.canOpenToolbar] is `ChatController.showToolbar`'s
/// silent-return guard, shared with the message select overlay's semantics
/// gate (#8721): a message the tap would no-op on must publish no "Select
/// message" button, so the two must never disagree.
void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await getTestClient();
    room = Room(id: '!chat:fakeServer.notExisting', client: client);
  });

  tearDown(() async {
    await client.dispose();
  });

  Event message({
    String body = 'buenos días',
    EventStatus status = EventStatus.synced,
    Map<String, dynamic>? unsigned,
  }) => Event(
    type: EventTypes.Message,
    eventId: r'$msg:fakeServer.notExisting',
    senderId: '@othertest:fakeServer.notExisting',
    originServerTs: DateTime.now(),
    status: status,
    content: {'msgtype': 'm.text', 'body': body},
    unsigned: unsigned,
    room: room,
  );

  test('a plain synced text message can open the toolbar', () {
    expect(message().canOpenToolbar, isTrue);
  });

  test('a redacted message cannot', () {
    final redacted = message(
      unsigned: {
        'redacted_because': {
          'event_id': r'$redaction:fakeServer.notExisting',
          'type': EventTypes.Redaction,
          'sender': '@othertest:fakeServer.notExisting',
          'origin_server_ts': 0,
          'content': <String, dynamic>{},
        },
      },
    );
    expect(redacted.redacted, isTrue, reason: 'harness must build a redaction');
    expect(redacted.canOpenToolbar, isFalse);
  });

  test('an empty-bodied message cannot', () {
    expect(message(body: '').canOpenToolbar, isFalse);
  });

  test('a still-sending message cannot', () {
    expect(message(status: EventStatus.sending).canOpenToolbar, isFalse);
  });
}

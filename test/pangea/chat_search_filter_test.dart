import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/chat_search/chat_search_filter.dart';
import 'get_test_client.dart';

/// The message tab of chat search must only surface events that carry
/// searchable message text. Everything else — state events, attachments,
/// undecryptable and redacted events — is rendered by the SDK as
/// `Unknown message format of type "<type>"` or `Redacted`, so it matches
/// arbitrary queries if it reaches the text comparison.
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

  Event event({
    required String type,
    required Map<String, Object?> content,
    Map<String, Object?>? unsigned,
  }) => Event(
    type: type,
    content: content,
    senderId: '@test:fakeServer.notExisting',
    eventId: '\$event',
    originServerTs: DateTime.utc(2026, 1, 1, 12),
    room: room,
    unsigned: unsigned,
  );

  Event message(String msgtype, String body) => event(
    type: EventTypes.Message,
    content: {'msgtype': msgtype, 'body': body},
  );

  test('matches the body of text, notice and emote messages', () {
    for (final msgtype in ChatSearchFilter.searchableMessageTypes) {
      expect(
        ChatSearchFilter.matches(
          message(msgtype, 'my parent is here'),
          'paren',
        ),
        isTrue,
        reason: msgtype,
      );
    }
  });

  test('match is case insensitive', () {
    expect(
      ChatSearchFilter.matches(
        message(MessageTypes.Text, 'My Parent'),
        'pArEn',
      ),
      isTrue,
    );
  });

  test('does not match a message whose body lacks the query', () {
    expect(
      ChatSearchFilter.matches(
        message(MessageTypes.Text, 'hello there'),
        'parent',
      ),
      isFalse,
    );
  });

  test('excludes state events that fall back to a placeholder body', () {
    for (final type in [
      EventTypes.SpaceParent,
      EventTypes.RoomName,
      EventTypes.GuestAccess,
      EventTypes.RoomCreate,
    ]) {
      final stateEvent = event(type: type, content: {});
      // The placeholder the SDK renders is what makes these false positives.
      expect(stateEvent.body, contains(type), reason: type);
      expect(
        ChatSearchFilter.matches(stateEvent, 'parent'),
        isFalse,
        reason: type,
      );
      expect(ChatSearchFilter.matches(stateEvent, 'a'), isFalse, reason: type);
    }
  });

  test(
    'excludes attachments, which carry a filename rather than message text',
    () {
      for (final msgtype in [
        MessageTypes.Image,
        MessageTypes.Video,
        MessageTypes.Audio,
        MessageTypes.File,
      ]) {
        expect(
          ChatSearchFilter.matches(
            message(msgtype, 'parent-photo.png'),
            'parent',
          ),
          isFalse,
          reason: msgtype,
        );
      }
    },
  );

  test('excludes events that could not be decrypted', () {
    final encrypted = event(
      type: EventTypes.Encrypted,
      content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
    );
    expect(ChatSearchFilter.matches(encrypted, 'encrypted'), isFalse);
  });

  test('excludes redacted messages', () {
    final redacted = event(
      type: EventTypes.Message,
      content: {},
      unsigned: {
        'redacted_because': {
          'type': EventTypes.Redaction,
          'content': <String, Object?>{},
          'sender': '@test:fakeServer.notExisting',
          'event_id': '\$redaction',
          'origin_server_ts': 0,
        },
      },
    );
    expect(redacted.body, 'Redacted');
    expect(ChatSearchFilter.matches(redacted, 'redacted'), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/user/direct_chat_contacts_extension.dart';
import 'get_test_client.dart';

/// The chat list's search finds a direct chat by the other person's username
/// as well as their display name, as the user searches do (#9322).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const friendId = '@jsmith42:fakeServer.notExisting';
  const i18n = MatrixDefaultLocalizations();

  late Client client;
  late Room dm;
  late Room group;

  Event stateEvent(
    Room room,
    String type,
    String stateKey,
    Map<String, Object> content,
  ) => Event(
    type: type,
    content: content,
    stateKey: stateKey,
    senderId: userId,
    eventId: '\$$type$stateKey${room.id}',
    originServerTs: DateTime.now(),
    room: room,
  );

  setUp(() async {
    client = await getTestClient();

    dm = Room(
      id: '!dm:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
    );
    dm.summary.mHeroes = [friendId];
    dm.setState(
      stateEvent(dm, EventTypes.RoomMember, friendId, {
        'membership': 'join',
        'displayname': 'Maria',
      }),
    );
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        friendId: [dm.id],
      },
    );

    group = Room(
      id: '!jsmith42group:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
    );
    group.setState(
      stateEvent(group, EventTypes.RoomName, '', {'name': 'Study group'}),
    );

    client.rooms.addAll([dm, group]);
  });

  tearDown(() async {
    await client.dispose();
  });

  test('a direct chat is found by the partner display name', () {
    expect(dm.getLocalizedDisplayname(i18n), 'Maria');
    expect(dm.matchesChatSearch('mar', i18n), isTrue);
  });

  test('a direct chat is found by the partner username, any case', () {
    expect(dm.matchesChatSearch('jsmith', i18n), isTrue);
    expect(dm.matchesChatSearch('JSmith42', i18n), isTrue);
  });

  test('a group is found by name only, not by a Matrix ID', () {
    expect(group.matchesChatSearch('study', i18n), isTrue);
    expect(group.matchesChatSearch('jsmith', i18n), isFalse);
  });

  test('a term that matches neither field finds nothing', () {
    expect(dm.matchesChatSearch('pedro', i18n), isFalse);
  });

  test('an empty term matches every chat', () {
    expect(dm.matchesChatSearch('', i18n), isTrue);
    expect(group.matchesChatSearch('', i18n), isTrue);
  });
}

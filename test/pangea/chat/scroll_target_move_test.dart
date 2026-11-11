import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/scroll_target_move.dart';
import '../get_test_client.dart';

/// CLIENT-CNG: jumping to a loaded event the current view filters out reloaded
/// the timeline three times and reported. The fix opens the view the event
/// belongs in; this pins which view that is.
void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await getTestClient();
    room = Room(id: '!1234:fakeServer.notExisting', client: client);
  });

  tearDown(() async {
    await client.dispose();
  });

  Event message(String id, {String? threadRoot}) => Event(
    type: EventTypes.Message,
    content: {
      'msgtype': 'm.text',
      'body': 'x',
      if (threadRoot != null)
        'm.relates_to': {'rel_type': 'm.thread', 'event_id': threadRoot},
    },
    senderId: '@test:fakeServer.notExisting',
    eventId: id,
    originServerTs: DateTime.utc(2026, 1, 1),
    room: room,
  );

  test('a thread reply seen from the main timeline opens its thread', () {
    final reply = message(r'$reply', threadRoot: r'$root');
    expect(reply.threadRootId, r'$root');
    expect(scrollTargetMove(reply, null), ScrollTargetMove.enterThread);
  });

  test('a reply in another thread opens that thread', () {
    final reply = message(r'$reply', threadRoot: r'$root');
    expect(scrollTargetMove(reply, r'$other'), ScrollTargetMove.enterThread);
  });

  test('a main-timeline message seen from a thread closes the thread', () {
    expect(
      scrollTargetMove(message(r'$main'), r'$root'),
      ScrollTargetMove.closeThread,
    );
  });

  test('an event already in this view needs no move', () {
    expect(scrollTargetMove(message(r'$main'), null), ScrollTargetMove.none);
    expect(
      scrollTargetMove(message(r'$reply', threadRoot: r'$root'), r'$root'),
      ScrollTargetMove.none,
    );
    expect(
      scrollTargetMove(message(r'$root'), r'$root'),
      ScrollTargetMove.none,
    );
  });
}

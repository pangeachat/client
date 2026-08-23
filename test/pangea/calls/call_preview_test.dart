import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/extensions/pangea_event_extension.dart';
import '../get_test_client.dart';

/// What the chat LIST shows for a room a call happened in.
///
/// The call's own machinery is not conversation: membership state, the ring
/// and the decline all pass through the room, and previewing any of them told
/// the learner nothing while burying the last real message. Exactly one call
/// event is worth a preview, and it is the card, which carries a plain body
/// written for this.
void main() {
  late Client client;

  setUpAll(() async {
    client = await getTestClient();
  });

  Event of(String type) => Event(
    type: type,
    content: const {'body': 'x'},
    senderId: '@a:server',
    eventId: '\$e',
    originServerTs: DateTime.now(),
    room: Room(id: '!r:server', client: client),
  );

  test('the call plumbing never becomes a room preview', () {
    for (final type in [
      EventTypes.GroupCallMember,
      PangeaEventTypes.callNotification,
      PangeaEventTypes.callDecline,
    ]) {
      expect(
        of(type).isVisibleLastEvent,
        isFalse,
        reason: '$type is not something to read in a chat list',
      );
    }
  });

  test('the call CARD is', () {
    expect(of(PangeaEventTypes.call).isVisibleLastEvent, isTrue);
  });
}

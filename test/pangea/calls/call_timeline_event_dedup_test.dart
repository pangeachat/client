import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../get_test_client.dart';

/// The first-per-key rule, pinned directly.
///
/// Matrix transaction ids dedup PER DEVICE, so the writer and the survivor
/// racing across the settle window can genuinely both post a card for one
/// call. The renderer is the idempotent receiver: only the FIRST card per
/// key in timeline order draws, on every client identically.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late Room room;

  setUpAll(() async {
    client = await getTestClient();
    // A real direct chat with @a:server. Only a card written by one of the two
    // people who were on the call can suppress another, so the pair has to be
    // established or nothing counts as a side.
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@a:server': ['!r:server'],
      },
    );
    room = Room(id: '!r:server', client: client);
  });

  tearDownAll(() => client.dispose());

  Event card(
    String id, {
    String? key,
    int ts = 1000,
    String sender = '@a:server',
    EventStatus status = EventStatus.synced,
  }) => Event(
    type: PangeaEventTypes.call,
    content: {
      'msgtype': PangeaEventTypes.call,
      'body': 'Voice call',
      'answered': true,
      CallRecord.callKeyField: ?key,
    },
    senderId: sender,
    eventId: id,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
    room: room,
    status: status,
  );

  test('the second card for one call is the duplicate', () {
    final first = card(r'$one', key: 'k', ts: 1000);
    final second = card(r'$two', key: 'k', ts: 2000);
    final all = [first, second];
    expect(CallTimelineEvent.isDuplicateOfEarlier(first, all), isFalse);
    expect(CallTimelineEvent.isDuplicateOfEarlier(second, all), isTrue);
  });

  test('the same moment is settled by event id, identically everywhere', () {
    final a = card(r'$aaa', key: 'k', ts: 1000);
    final b = card(r'$bbb', key: 'k', ts: 1000);
    // Whatever order the list arrives in, the same one survives.
    for (final all in [
      [a, b],
      [b, a],
    ]) {
      expect(CallTimelineEvent.isDuplicateOfEarlier(a, all), isFalse);
      expect(CallTimelineEvent.isDuplicateOfEarlier(b, all), isTrue);
    }
  });

  test('different keys are different calls', () {
    final one = card(r'$one', key: 'k1', ts: 1000);
    final two = card(r'$two', key: 'k2', ts: 2000);
    final all = [one, two];
    expect(CallTimelineEvent.isDuplicateOfEarlier(two, all), isFalse);
  });

  test('keyless legacy cards always draw', () {
    final legacy1 = card(r'$one', ts: 1000);
    final legacy2 = card(r'$two', ts: 2000);
    final all = [legacy1, legacy2];
    expect(CallTimelineEvent.isDuplicateOfEarlier(legacy1, all), isFalse);
    expect(CallTimelineEvent.isDuplicateOfEarlier(legacy2, all), isFalse);
  });

  test('a card that never sent cannot suppress the one that did', () {
    // The failed optimistic echo is already hidden by its own rule; letting
    // it ALSO count as "the first card" would hide the real one and the call
    // would vanish from both.
    final failed = card(
      r'$dead',
      key: 'k',
      ts: 1000,
      status: EventStatus.error,
    );
    final real = card(r'$real', key: 'k', ts: 2000);
    final all = [failed, real];
    expect(CallTimelineEvent.isDuplicateOfEarlier(real, all), isFalse);
  });

  group('a card from someone who was not on the call', () {
    test('cannot suppress the real one', () {
      // The key is the caller's membership event id, and both sides know it
      // DURING the call -- long before either writes its card. Without a
      // sender check anyone else in the room could write a card carrying the
      // right key the moment the call starts, win the earliest-timestamp
      // tie-break, and hide the truthful card behind their own permanently.
      // Setting `declined` on the forgery also removed the tap target that
      // opens the transcript, so real halves became unreachable.
      final real = card(r'$real', key: 'k', ts: 2000);
      final forged = card(
        r'$forged',
        key: 'k',
        ts: 1000,
        sender: '@stranger:evil.example',
      );

      expect(
        CallTimelineEvent.isDuplicateOfEarlier(real, [real, forged]),
        isFalse,
        reason: 'the truthful card is still drawn',
      );
    });

    test('a genuine earlier card from the other side still suppresses', () {
      // The rule has to keep working: both devices can write a card for one
      // call, and exactly one is drawn.
      final mine = card(
        r'$mine',
        key: 'k',
        ts: 2000,
        sender: '@test:fakeServer.notExisting',
      );
      final theirs = card(r'$theirs', key: 'k', ts: 1000);

      expect(
        CallTimelineEvent.isDuplicateOfEarlier(mine, [mine, theirs]),
        isTrue,
      );
    });
  });

  group('when the peer has left and cannot be identified', () {
    test('one call still draws ONE card, not two', () {
      // The case this feature is built around. Their card syncs late, we write
      // a survivor card for the same call, then they leave the room -- so the
      // peer can no longer be worked out. Asking the raw set of sides whether
      // their id belongs made it answer false for a real person, so our later
      // card was never compared against their genuinely earlier one and both
      // drew: one call, twice, in the conversation.
      client.accountData.remove('m.direct');
      final wide = Room(
        id: '!wide:server',
        client: client,
        summary: RoomSummary.fromJson({
          'm.joined_member_count': 3,
          'm.invited_member_count': 0,
          'm.heroes': <String>[],
        }),
      );
      for (final id in [
        '@test:fakeServer.notExisting',
        '@a:server',
        '@third:server',
      ]) {
        wide.setState(
          Event(
            type: EventTypes.RoomMember,
            stateKey: id,
            content: const {'membership': 'join'},
            senderId: id,
            eventId: '\$m-\$id',
            originServerTs: DateTime.now(),
            room: wide,
          ),
        );
      }

      Event cardFrom(String sender, String id, int ts) => Event(
        type: PangeaEventTypes.call,
        content: {
          'msgtype': PangeaEventTypes.call,
          'answered': true,
          CallRecord.callKeyField: 'k',
        },
        senderId: sender,
        eventId: id,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
        room: wide,
        status: EventStatus.synced,
      );

      final theirs = cardFrom('@a:server', r'$theirs', 1000);
      final mine = cardFrom('@test:fakeServer.notExisting', r'$mine', 2000);
      final all = [theirs, mine];

      expect(
        CallTimelineEvent.isDuplicateOfEarlier(theirs, all),
        isFalse,
        reason: 'the earliest card is the one that draws',
      );
      expect(
        CallTimelineEvent.isDuplicateOfEarlier(mine, all),
        isTrue,
        reason: 'and the later one is suppressed, peer identifiable or not',
      );
    });
  });
}

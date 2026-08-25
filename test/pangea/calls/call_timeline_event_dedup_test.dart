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

  group('when the peer cannot be identified', () {
    Room wideRoom() {
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
      return wide;
    }

    Event cardFrom(Room r, String sender, String id, int ts) => Event(
      type: PangeaEventTypes.call,
      content: {
        'msgtype': PangeaEventTypes.call,
        'answered': true,
        CallRecord.callKeyField: 'k',
      },
      senderId: sender,
      eventId: id,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
      room: r,
      status: EventStatus.synced,
    );

    test('a card that cannot vouch for itself cannot hide the real one', () {
      // The attack. A third party who was in the room during the call knows
      // the call key -- it is ordinary room state -- so they can post a card
      // carrying it with an earlier timestamp than the real one, which is
      // written only at hangup. Letting that suppress made the truthful card
      // vanish and took the transcript's only tap target with it.
      final wide = wideRoom();
      final forged = cardFrom(wide, '@third:server', r'$forged', 1000);
      final real = cardFrom(
        wide,
        '@test:fakeServer.notExisting',
        r'$real',
        2000,
      );

      expect(
        CallTimelineEvent.isDuplicateOfEarlier(real, [forged, real]),
        isFalse,
        reason: 'the real card still draws',
      );
    });

    test('the stated cost: two genuine cards for one call both draw', () {
      // Deliberate, and a reversal of the earlier choice here. Neither card
      // can prove itself entitled to suppress the other while the peer is
      // unidentifiable, so both are kept. A visible duplicate of a call that
      // really happened is a far better failure than a real call disappearing
      // -- which is what preferring one card bought, once a forgery could be
      // the one preferred.
      final wide = wideRoom();
      final theirs = cardFrom(wide, '@a:server', r'$theirs', 1000);
      final mine = cardFrom(
        wide,
        '@test:fakeServer.notExisting',
        r'$mine',
        2000,
      );

      expect(
        CallTimelineEvent.isDuplicateOfEarlier(mine, [theirs, mine]),
        isFalse,
      );
      expect(
        CallTimelineEvent.isDuplicateOfEarlier(theirs, [theirs, mine]),
        isFalse,
      );
    });

    test('an identifiable peer still collapses the duplicate', () {
      // The ordinary case has to keep working: when we can tell who the other
      // side is, two cards for one call still draw once.
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@a:server': ['!r:server'],
        },
      );
      final theirs = card(r'$theirs', key: 'k', ts: 1000);
      final mine = card(
        r'$mine',
        key: 'k',
        ts: 2000,
        sender: '@test:fakeServer.notExisting',
      );

      expect(
        CallTimelineEvent.isDuplicateOfEarlier(mine, [theirs, mine]),
        isTrue,
      );
    });
  });

  group('the chat list keeps the same card the conversation draws', () {
    test('a later survivor card does not take the line from the first', () {
      // Real and deterministic, not a coincidence. The writer's card is sent
      // at hangup; delivery to the other device is delayed past the settle
      // window by ordinary network flakiness; that device writes a survivor
      // card with the same call key and its own measured duration. Both are
      // genuine. The conversation keeps the earlier one; the list took
      // whatever arrived last, so one call was described twice, differently,
      // and the survivor card always won because it is always the later one.
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@a:server': ['!r:server'],
        },
      );
      final theirs = card(r'$theirs', key: 'k', ts: 1000);
      final survivor = card(
        r'$survivor',
        key: 'k',
        ts: 2000,
        sender: '@test:fakeServer.notExisting',
      );

      expect(
        callCardMayTakeTheChatListLine(theirs, survivor),
        isFalse,
        reason: 'the line keeps the card the conversation draws',
      );
      expect(
        CallTimelineEvent.isDuplicateOfEarlier(survivor, [theirs, survivor]),
        isTrue,
        reason: 'and the conversation agrees, from the other direction',
      );
    });

    test('a card for a DIFFERENT call always takes the line', () {
      // The rule is only about one call described twice. A newer call is the
      // newest thing that happened in the room and belongs on the line.
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@a:server': ['!r:server'],
        },
      );
      final older = card(r'$older', key: 'k1', ts: 1000);
      final newer = card(r'$newer', key: 'k2', ts: 2000);

      expect(callCardMayTakeTheChatListLine(older, newer), isTrue);
    });

    test('an earlier card for the same call DOES take the line', () {
      // Arrival order is not timestamp order. If the earlier card syncs
      // second, it still becomes the line, because it is the one drawn.
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@a:server': ['!r:server'],
        },
      );
      final survivor = card(
        r'$survivor',
        key: 'k',
        ts: 2000,
        sender: '@test:fakeServer.notExisting',
      );
      final theirs = card(r'$theirs', key: 'k', ts: 1000);

      expect(callCardMayTakeTheChatListLine(survivor, theirs), isTrue);
    });

    test('nothing on the line yet means anything may take it', () {
      expect(
        callCardMayTakeTheChatListLine(null, card(r'$a', key: 'k')),
        isTrue,
      );
    });
  });

  group('what may hold the chat-list line', () {
    void asDirectChat() {
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@a:server': ['!r:server'],
        },
      );
    }

    test('a card that renders as nothing cannot take the line', () {
      // A third party who was in the room during the call knows the call key.
      // Their card fails the "could be real" check, so the list renders
      // nothing for it -- and letting it win the slot took the summary away
      // from a real call the conversation was still drawing. A blank row, not
      // a wrong one, which is harder to notice and worse.
      asDirectChat();
      final real = card(r'$real', key: 'k', ts: 1000);
      final forged = card(
        r'$forged',
        key: 'k',
        ts: 2000,
        sender: '@stranger:evil.example',
      );

      expect(callCardMayTakeTheChatListLine(real, forged), isFalse);
    });

    test('a card whose send FAILED cannot take the line', () {
      asDirectChat();
      final real = card(r'$real', key: 'k1', ts: 1000);
      final failed = card(r'$failed', key: 'k2', ts: 2000);
      failed.status = EventStatus.error;

      expect(callCardMayTakeTheChatListLine(real, failed), isFalse);
    });

    test('the SAME event advancing its own status is always let through', () {
      // A locally sent event is echoed at status sending and, if the send
      // fails, echoed again as the SAME event id with status error. Ranking
      // those two is a tie -- same timestamp, same id -- which refused the
      // update and froze the line on the stale sending copy, so the list
      // showed a cheerful "Voice call" for a call the peer never received
      // while the conversation showed nothing.
      asDirectChat();
      final sending = card(r'$mine', key: 'k', ts: 1000);
      sending.status = EventStatus.sending;
      final errored = card(r'$mine', key: 'k', ts: 1000);
      errored.status = EventStatus.error;

      expect(
        callCardMayTakeTheChatListLine(sending, errored),
        isTrue,
        reason: 'the record must be allowed to tell the truth about itself',
      );
    });

    test('the accepted event replaces its own local echo', () {
      // The hop every successfully sent card makes: the local echo is keyed by
      // the transaction id, and the accepted event comes back under a real
      // event id carrying that transaction id. Both echoes share one
      // timestamp, so the tie used to be settled by comparing a transaction id
      // string against a `\$`-prefixed event id -- correct today only because
      // this app's transaction ids start with a letter, which sorts after
      // `\$`. Luck, not an invariant.
      asDirectChat();
      final echo = card(r'$pangea.call.abc', key: 'k', ts: 1000);
      echo.status = EventStatus.sending;
      final accepted = Event(
        type: PangeaEventTypes.call,
        content: {'answered': true, CallRecord.callKeyField: 'k'},
        senderId: '@a:server',
        eventId: r'$real-server-id',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        room: Room(id: '!r:server', client: client),
        status: EventStatus.synced,
        unsigned: const {'transaction_id': r'$pangea.call.abc'},
      );

      expect(
        callCardMayTakeTheChatListLine(echo, accepted),
        isTrue,
        reason: 'a record confirming itself is not a rival card',
      );
    });

    test('an unidentifiable peer is a shrug, not a refusal', () {
      // The distinction the previous version could not draw. Nobody being
      // identifiable must not be treated the same as this sender being
      // identifiably not a participant.
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
      Event inWide(String sender, String id, int ts) => Event(
        type: PangeaEventTypes.call,
        content: {'answered': true, CallRecord.callKeyField: 'k'},
        senderId: sender,
        eventId: id,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
        room: wide,
        status: EventStatus.synced,
      );

      expect(
        callCardMayTakeTheChatListLine(
          inWide('@a:server', r'$one', 1000),
          inWide('@third:server', r'$two', 2000),
        ),
        isTrue,
        reason: 'neither can vouch, so neither is refused',
      );
    });

    test('an ordinary message still takes the line', () {
      // Only call cards are ours to arbitrate.
      asDirectChat();
      final callCard = card(r'$c', key: 'k', ts: 1000);
      final message = Event(
        type: EventTypes.Message,
        content: const {'msgtype': 'm.text', 'body': 'hola'},
        // NOT one of the two sides. Without the type guard this event would
        // be judged by a rule written for call cards and refused, so the chat
        // list would stop updating for ordinary messages from anyone the
        // call rules do not recognise.
        senderId: '@third:server',
        eventId: r'$msg',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(2000),
        room: Room(id: '!r:server', client: client),
        status: EventStatus.synced,
      );

      expect(callCardMayTakeTheChatListLine(callCard, message), isTrue);
    });
  });
}

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../get_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const me = '@test:fakeServer.notExisting';

  late Client client;

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  Event card({
    required EventStatus status,
    String caller = me,
    bool answered = false,
    bool declined = true,
  }) {
    final room = Room(id: '!c:fakeServer.notExisting', client: client);
    return Event(
      type: PangeaEventTypes.call,
      content: {
        'caller': caller,
        'answered': answered,
        'declined': declined,
        'duration_ms': 0,
      },
      senderId: me,
      eventId: r'$card',
      originServerTs: DateTime.now(),
      room: room,
      status: status,
    );
  }

  Future<void> pump(WidgetTester tester, Event event) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        // No surrounding timeline here: the dedup rule has its own suite, and
        // these tests are about how ONE card reads.
        home: Scaffold(body: CallTimelineEvent(event, timeline: null)),
      ),
    );
    // The localisations delegate resolves asynchronously; without this the
    // first frame carries no strings and every text assertion finds nothing.
    await tester.pumpAndSettle();
  }

  testWidgets('a card that reached the server is drawn', (tester) async {
    await pump(tester, card(status: EventStatus.synced));
    expect(find.text('Call declined'), findsOneWidget);
  });

  testWidgets('a card whose send FAILED is not drawn at all', (tester) async {
    // The SDK does not drop a failed send: it keeps the optimistic echo in the
    // LOCAL timeline and marks it errored. Nothing retries it and the peer never
    // receives it, so drawing it puts a call in one person's history that is
    // simply absent from the other's -- which is exactly how one account came to
    // show an extra "Call declined" that the other did not have.
    await pump(tester, card(status: EventStatus.error));
    expect(find.text('Call declined'), findsNothing);
    expect(find.byType(Icon), findsNothing, reason: 'nothing at all is drawn');
  });

  testWidgets('a card still in flight is drawn, because it may yet land', (
    tester,
  ) async {
    await pump(tester, card(status: EventStatus.sending));
    expect(find.text('Call declined'), findsOneWidget);
  });

  group('the caller field, which is room content', () {
    Event withCaller(Object? caller, {required String sender}) {
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@friend:server': ['!c:fakeServer.notExisting'],
        },
      );
      final room = Room(id: '!c:fakeServer.notExisting', client: client);
      return Event(
        type: PangeaEventTypes.call,
        content: {
          'caller': caller,
          'answered': true,
          'declined': false,
          'duration_ms': 1000,
        },
        senderId: sender,
        eventId: r'$card',
        originServerTs: DateTime.now(),
        room: room,
        status: EventStatus.synced,
      );
    }

    test('a caller naming a stranger is ignored, and the writer stands in', () {
      // The discriminating case: this card says WE wrote it, and names
      // somebody who is not either of us. Believing the field there would let
      // a crafted card decide the direction of a call between two other
      // people; falling back to the writer is where this stood before the
      // field existed.
      expect(
        callWasOutgoing(withCaller('@stranger:evil.example', sender: me)),
        isTrue,
        reason: 'we wrote it, so it was ours',
      );
      expect(
        callWasOutgoing(
          withCaller('@stranger:evil.example', sender: '@friend:server'),
        ),
        isFalse,
        reason: 'they wrote it, so it was theirs',
      );
    });

    test('a caller that is not a user id at all is ignored', () {
      // Also the crash: this value used to be cast to String? unguarded on the
      // path that opens the transcript.
      expect(callWasOutgoing(withCaller(123, sender: me)), isTrue);
      expect(callWasOutgoing(withCaller(null, sender: me)), isTrue);
    });

    test('a caller naming one of the two real sides is believed', () {
      // The field has to keep working: the card is written by the survivor as
      // often as by the caller, which is the whole reason it exists.
      expect(
        callWasOutgoing(withCaller(me, sender: '@friend:server')),
        isTrue,
        reason: 'they wrote it, but it says we called',
      );
      expect(
        callWasOutgoing(withCaller('@friend:server', sender: me)),
        isFalse,
        reason: 'we wrote it, but it says they called',
      );
    });

    test(
      'the peer can still claim either of us dialled -- documented limit',
      () {
        // Not a fix, a boundary. Both of these are the peer writing the card and
        // naming whichever of the two real parties it likes, and both are
        // believed, because there is no independent record of who dialled. The
        // cost is a wrong arrow between two people who were really talking. No
        // third party can be inserted, which is the part that mattered.
        expect(
          callWasOutgoing(withCaller(me, sender: '@friend:server')),
          isTrue,
        );
        expect(
          callWasOutgoing(
            withCaller('@friend:server', sender: '@friend:server'),
          ),
          isFalse,
        );
      },
    );
  });

  group('a card from somebody who was not on the call', () {
    Event strangerCard() {
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@friend:server': ['!c:fakeServer.notExisting'],
        },
      );
      final room = Room(id: '!c:fakeServer.notExisting', client: client);
      return Event(
        type: PangeaEventTypes.call,
        content: {
          'caller': '@friend:server',
          'answered': true,
          'declined': false,
          'duration_ms': 134000,
        },
        senderId: '@stranger:evil.example',
        eventId: r'$forged',
        originServerTs: DateTime.now(),
        room: room,
        status: EventStatus.synced,
      );
    }

    testWidgets('is not drawn at all', (tester) async {
      // Anyone in the room can send an event of this type. The suppression
      // rule already asked who sent a card that was trying to hide another;
      // the card being DRAWN was never asked. So a member who was not on the
      // call could post one with an answered flag, a duration and a transcript
      // affordance, and it read as a call that never happened.
      await pump(tester, strangerCard());

      expect(find.text('Voice call'), findsNothing);
      expect(find.byType(Icon), findsNothing, reason: 'nothing at all');
    });
  });

  group('when the peer cannot be worked out', () {
    /// A room that is not a direct chat and has no single other side: three
    /// people have been here, so [callPeerOf] cannot name one.
    Room unresolvable() {
      client.accountData.remove('m.direct');
      final r = Room(
        id: '!c:fakeServer.notExisting',
        client: client,
        summary: RoomSummary.fromJson({
          'm.joined_member_count': 3,
          'm.invited_member_count': 0,
          'm.heroes': <String>[],
        }),
      );
      for (final id in [me, '@friend:server', '@third:server']) {
        r.setState(
          Event(
            type: EventTypes.RoomMember,
            stateKey: id,
            content: const {'membership': 'join'},
            senderId: id,
            eventId: '\$m-\$id',
            originServerTs: DateTime.now(),
            room: r,
          ),
        );
      }
      return r;
    }

    Event cardIn(Room r, {required String sender, Object? caller}) => Event(
      type: PangeaEventTypes.call,
      content: {
        'caller': caller,
        'answered': true,
        'declined': false,
        'duration_ms': 8000,
      },
      senderId: sender,
      eventId: r'$c',
      originServerTs: DateTime.now(),
      room: r,
      status: EventStatus.synced,
    );

    test('a real call is not hidden because we cannot confirm who was on it', () {
      // Not knowing who the other side is happens on its own -- they leave the
      // room. Reading that as "they were not a participant" hid the card for a
      // call that really happened, on every surface, and the transcript with
      // it.
      final r = unresolvable();
      expect(callCardCouldBeReal(cardIn(r, sender: '@friend:server')), isTrue);
    });

    test('a known peer still excludes everyone else', () {
      // The anti-forgery rule has to keep working wherever it can be applied.
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@friend:server': ['!c:fakeServer.notExisting'],
        },
      );
      final r = Room(id: '!c:fakeServer.notExisting', client: client);
      expect(
        callCardCouldBeReal(cardIn(r, sender: '@stranger:evil.example')),
        isFalse,
      );
      expect(callCardCouldBeReal(cardIn(r, sender: '@friend:server')), isTrue);
    });

    test(
      'a truthful caller is not discarded because it cannot be confirmed',
      () {
        // Our own survivor card, correctly naming the peer who called us, read
        // back as a call WE placed -- nobody lied, the unresolved peer simply
        // threw away a true value.
        final r = unresolvable();
        expect(
          callWasOutgoing(cardIn(r, sender: me, caller: '@friend:server')),
          isFalse,
          reason: 'they called, and our card says so',
        );
      },
    );
  });
}

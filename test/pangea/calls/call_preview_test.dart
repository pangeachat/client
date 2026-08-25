import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/extensions/pangea_event_extension.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item_subtitle.dart';
import '../get_test_client.dart';

/// What the chat LIST shows for a room a call happened in.
///
/// The call's own machinery is not conversation: membership state, the ring
/// and the decline all pass through the room, and previewing any of them told
/// the learner nothing while burying the last real message. Exactly one call
/// event is worth a preview, and it is the card, which carries a plain body
/// written for this.
/// A real direct chat with `@a:server`.
///
/// The card's stated caller is believed only when it names one of the two real
/// sides of the call, and the peer is read from m.direct -- so a room that is
/// not a direct chat has no second side for the caller to be.
Room _directChat(Client client) {
  client.accountData['m.direct'] = BasicEvent(
    type: 'm.direct',
    content: {
      '@a:server': ['!r:server'],
    },
  );
  return Room(id: '!r:server', client: client);
}

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
    room: _directChat(client),
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

  // Being eligible as a last event is only half of it. Left to the SDK the
  // list then reads "User sent a pangea.call event", which is worse than the
  // "No messages yet" it replaced. The list says what the conversation says.
  Event card({
    bool answered = true,
    bool declined = false,
    bool video = false,
    int durationMs = 8000,
    String sender = '@a:server',
    String? caller,
  }) => Event(
    type: PangeaEventTypes.call,
    content: {
      'caller': caller ?? sender,
      'answered': answered,
      'declined': declined,
      'video': video,
      'duration_ms': durationMs,
    },
    senderId: sender,
    eventId: r'$card',
    originServerTs: DateTime.now(),
    room: _directChat(client),
  );

  Future<String> preview(WidgetTester tester, Event event) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ChatListItemSubtitle(
            room: event.room,
            style: const TextStyle(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<Text>(find.byType(Text)).data!;
  }

  /// The same, but able to express "the list shows nothing here".
  ///
  /// Distinct from an empty string: a call the conversation refuses to draw
  /// gets no line at all, and a helper that insists on exactly one Text cannot
  /// tell that from a failure.
  Future<String?> previewOrNothing(WidgetTester tester, Event event) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ChatListItemSubtitle(
            room: event.room,
            style: const TextStyle(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final texts = tester.widgetList<Text>(find.byType(Text));
    return texts.isEmpty ? null : texts.first.data;
  }

  testWidgets('an answered call reads as a call, with its length', (
    tester,
  ) async {
    final event = card();
    event.room.lastEvent = event;
    expect(await preview(tester, event), 'Voice call · 0:08');
  });

  testWidgets('a missed call reads as missed, not as an event', (tester) async {
    final event = card(answered: false, durationMs: 0);
    event.room.lastEvent = event;
    final text = await preview(tester, event);
    expect(text, 'Missed call');
    expect(text, isNot(contains('pangea.call')));
  });

  testWidgets('a declined call, and the caller reads the other half', (
    tester,
  ) async {
    final theirs = card(answered: false, declined: true);
    theirs.room.lastEvent = theirs;
    expect(await preview(tester, theirs), 'You declined this call');

    final mine = card(answered: false, declined: true, sender: client.userID!);
    mine.room.lastEvent = mine;
    expect(await preview(tester, mine), 'Call declined');
  });

  testWidgets('who called is the stated caller, not who wrote the card', (
    tester,
  ) async {
    // The writer is chosen deterministically and is not always the side that
    // called: a card recovered by the survivor is written by the OTHER one.
    // Reading direction off the sender made the chat list say the opposite of
    // the card in the conversation about the same call.
    final recovered = card(
      answered: false,
      declined: false,
      durationMs: 0,
      sender: client.userID!, // we wrote it
      caller: '@a:server', // they called
    );
    recovered.room.lastEvent = recovered;
    expect(await preview(tester, recovered), 'Missed call');
  });

  testWidgets('a video call says so', (tester) async {
    final event = card(video: true, durationMs: 62000);
    event.room.lastEvent = event;
    expect(await preview(tester, event), 'Video call · 1:02');
  });

  testWidgets('a call the conversation refuses to draw is not in the list', (
    tester,
  ) async {
    // The card in the conversation already refuses to draw a send that
    // failed: nothing retries it, the peer never receives it, and a record
    // only one side holds reads as a call that never happened. The list had
    // no such check, so the same event vanished from the conversation and
    // stayed here as a plausible "Voice call" the other person never saw.
    final failed = card(durationMs: 8000);
    failed.status = EventStatus.error;
    failed.room.lastEvent = failed;

    expect(await previewOrNothing(tester, failed), isNull);
  });

  testWidgets('a card from somebody who was not on the call gets no line', (
    tester,
  ) async {
    // The two surfaces are supposed to agree about the same call, and the
    // conversation refuses to draw this one at all.
    final forged = card(sender: '@stranger:evil.example');
    forged.room.lastEvent = forged;

    expect(await previewOrNothing(tester, forged), isNull);
  });

  testWidgets('an unshowable card does not claim the whole room is empty', (
    tester,
  ) async {
    // The room may be full of real messages that simply are not the newest
    // event. "Empty chat" is a claim about all of it.
    final failed = card();
    failed.status = EventStatus.error;
    failed.room.lastEvent = failed;

    expect(await previewOrNothing(tester, failed), isNull);
  });
}

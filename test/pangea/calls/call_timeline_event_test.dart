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
}

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/course_header_actions.dart';
import '../get_test_client.dart';

/// #8866 — the focus-on-map button is gated on the course having something
/// on the map to fit, but it must not blink out while the outline is merely
/// still loading: the context bar and the course card each warm their own
/// loader, so a loading-state gap showed as a flicker at every hand-off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  Future<QuestObjectivesLoader> pump(WidgetTester tester) async {
    final room = Room(
      id: '!course:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
    );
    final loader = QuestObjectivesLoader(client: client);
    addTearDown(loader.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: CourseHeaderActions(room: room, objectivesProvider: loader),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return loader;
  }

  testWidgets('focus-on-map shows while the outline is loading', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });

  testWidgets('focus-on-map hides once the outline settles with nothing '
      'to fit', (tester) async {
    final loader = await pump(tester);

    // No quest at all — the loader settles on a missing-quest error.
    await loader.loadOutline(null);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.my_location), findsNothing);
  });
}

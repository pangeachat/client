import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #9075 — a saved session's row carries the learner's own numbers from the
/// summary saved with the session: the XP they earned and how many distinct
/// vocabulary and grammar items they used (activities.instructions.md, "The
/// Stars list").
void main() {
  late Client client;

  const roomId = '!session:fakeServer.notExisting';
  const ownUserId = '@test:fakeServer.notExisting';
  const otherUserId = '@alice:example.org';

  setUpAll(() {
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
    // The summary is stored under the viewer's L1, read off the static
    // controller.
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Map<String, dynamic> construct(String lemma, String type) => {
    'lemma': lemma,
    'type': type,
    'cat': 'n',
    'times_used': 10,
  };

  /// A session room holding a generated summary: the learner used three vocab
  /// items and two grammar items, for 50 XP, and a coursemate's own items are
  /// in the same event without counting toward the learner's row.
  Room makeRoom({bool withSummary = true}) {
    final room = Room(id: roomId, client: client);
    room.setState(
      Event(
        type: EventTypes.RoomName,
        content: {'name': 'Ordering coffee'},
        stateKey: '',
        senderId: otherUserId,
        eventId: '\$name',
        originServerTs: DateTime.utc(2026, 1, 1),
        room: room,
      ),
    );
    if (withSummary) {
      room.setState(
        Event(
          type: PangeaEventTypes.activitySummary,
          content: {
            'summary': {
              'summary': 'A short chat at the counter.',
              'participants': [
                {
                  'participant_id': ownUserId,
                  'feedback': 'Nicely done.',
                  'cefr_level': 'A2',
                  'superlatives': [],
                },
              ],
            },
            'analytics': {
              ownUserId: [
                construct('café', 'vocab'),
                construct('leche', 'vocab'),
                construct('azúcar', 'vocab'),
                construct('Number', 'morph'),
                construct('Tense', 'morph'),
              ],
              otherUserId: [construct('mesa', 'vocab')],
            },
          },
          stateKey: 'en',
          senderId: otherUserId,
          eventId: '\$summary',
          originServerTs: DateTime.utc(2026, 1, 1),
          room: room,
        ),
      );
    }
    return room;
  }

  Future<void> pump(
    WidgetTester tester,
    Room room, {
    bool selected = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: AnalyticsActivityItem(room: room, selected: selected),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a saved summary puts the learner\'s own stats on the row', (
    tester,
  ) async {
    await pump(tester, makeRoom());

    expect(find.text('50 XP'), findsOneWidget);
    // The learner's three vocab and two grammar items — the coursemate's item
    // belongs to their row, not this one.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);
  });

  testWidgets('the counts carry a spoken label the bare number cannot', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, makeRoom());

    expect(find.bySemanticsLabel(RegExp('3 vocab items used')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('2 grammar items used')), findsWidgets);

    semantics.dispose();
  });

  testWidgets('a session with no summary shows no stats and no level', (
    tester,
  ) async {
    await pump(tester, makeRoom(withSummary: false));

    expect(find.text('Ordering coffee'), findsOneWidget);
    expect(find.textContaining('XP'), findsNothing);
    expect(find.text('A2'), findsNothing);
  });

  testWidgets(
    'XP drops the gold on the selected fill, which it fails against',
    (tester) async {
      await pump(tester, makeRoom(), selected: true);

      final context = tester.element(find.text('50 XP'));
      final theme = Theme.of(context);
      expect(
        tester.widget<Text>(find.text('50 XP')).style?.color,
        theme.colorScheme.onSurface,
      );
      expect(
        tester.widget<Text>(find.text('50 XP')).style?.color,
        isNot(theme.pangea.gold),
      );
    },
  );
}

import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #9033 — a Stars row whose activity plan is missing (hydrating from CMS, or
/// gone from the backend) or whose plan carries an empty title rendered a blank
/// row. The session room is named after the activity at creation, so the row
/// falls back to the room name — the rung the start page's archived session
/// already lands on (activities.instructions.md, "When the activity can't be
/// fetched").
void main() {
  late Client client;

  const roomId = '!session:fakeServer.notExisting';
  const roomName = 'First meeting in San Antonio';
  const senderId = '@alice:example.org';

  setUpAll(() {
    // `Avatar` resolves the bot name from the environment at build time.
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
    // The row's CEFR badge reads the viewer L1 off the static controller.
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  ActivityPlanModel plan(String title) => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: 'travel',
      mode: 'Roleplay',
      objective: 'introduce yourself',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'es',
      numberOfParticipants: 2,
    ),
    title: title,
    learningObjective: 'lo',
    instructions: 'i',
    vocab: const [],
    activityId: 'act-1',
  );

  /// A session room named [roomName], carrying [planTitle]'s plan embedded in
  /// state — or no plan state at all when [planTitle] is null.
  Room makeRoom({String? planTitle}) {
    final room = Room(id: roomId, client: client);
    room.setState(
      Event(
        type: EventTypes.RoomName,
        content: {'name': roomName},
        stateKey: '',
        senderId: senderId,
        eventId: '\$name',
        originServerTs: DateTime.utc(2026, 1, 1),
        room: room,
      ),
    );
    if (planTitle != null) {
      room.setState(
        Event(
          type: PangeaEventTypes.activityPlan,
          content: plan(planTitle).toJson(),
          stateKey: '',
          senderId: senderId,
          eventId: '\$plan',
          originServerTs: DateTime.utc(2026, 1, 1),
          room: room,
        ),
      );
    }
    return room;
  }

  Future<void> pump(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: AnalyticsActivityItem(room: room)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no plan in state falls back to the room name', (tester) async {
    await pump(tester, makeRoom());

    expect(find.text(roomName), findsOneWidget);
  });

  testWidgets('a plan with an empty title falls back to the room name', (
    tester,
  ) async {
    await pump(tester, makeRoom(planTitle: ''));

    expect(find.text(roomName), findsOneWidget);
  });

  testWidgets('a plan with a title still wins over the room name', (
    tester,
  ) async {
    await pump(tester, makeRoom(planTitle: 'Ordering coffee'));

    expect(find.text('Ordering coffee'), findsOneWidget);
    expect(find.text(roomName), findsNothing);
  });
}

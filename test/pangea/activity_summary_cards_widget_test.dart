import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_analytics_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_chat_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_finished_status_message.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_user_summaries_widget.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_activity_chat_pangea_controller.dart';
import 'get_test_client.dart';

/// A learner sees their own card in the chat as soon as they finish, beside
/// the bar that says they are waiting for the rest; each card loads and fails
/// on its own, and the others' cards join as each of them finishes (#795).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bot = '@bot:example.org';
  const learner = '@test:fakeServer.notExisting';
  const coursemate = '@alice:example.org';
  const roomId = '!cards:fakeServer.notExisting';

  late Client client;
  var eventCount = 0;

  setUpAll(() async {
    dotenv.testLoad(fileInput: 'BOT_NAME=$bot');
    final tempDir = await Directory.systemTemp.createTemp('summary_cards');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    // Avatar reads the bot's name through a GetStorage box.
    await GetStorage.init('env_override');
    MatrixState.pangeaController = ActivityChatTestPangeaController();
  });

  setUp(() async => client = await getTestClient());
  tearDown(() => client.dispose());

  void setState(
    Room room,
    String type,
    String stateKey,
    Map<String, dynamic> content, {
    String sender = learner,
  }) => room.setState(
    Event(
      type: type,
      stateKey: stateKey,
      content: content,
      senderId: sender,
      eventId: '\$event${eventCount++}',
      originServerTs: DateTime.now(),
      room: room,
    ),
  );

  /// A two-learner activity, or with [botPartner] the learner and the bot,
  /// with the bot in the room and the learner's own analytics already
  /// written.
  Room activityRoom({
    bool learnerDone = true,
    bool coursemateDone = false,
    bool botPartner = false,
  }) {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    setState(
      room,
      PangeaEventTypes.activityRole,
      '',
      ActivityRolesModel({
        'role1': ActivityRoleModel(
          id: 'role1',
          userId: learner,
          role: 'Customer',
          finishedAt: learnerDone ? DateTime.utc(2026) : null,
        ),
        'role2': ActivityRoleModel(
          id: 'role2',
          userId: botPartner ? bot : coursemate,
          role: 'Barista',
          finishedAt: coursemateDone ? DateTime.utc(2026) : null,
        ),
      }).toJson(),
    );
    for (final userId in [learner, coursemate, bot]) {
      setState(room, EventTypes.RoomMember, userId, {
        'membership': 'join',
      }, sender: userId);
    }
    setState(
      room,
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.learnerAnalytics(learner),
      ActivitySummaryAnalyticsModel().toJson(),
    );
    return room;
  }

  ParticipantSummaryModel feedback(String userId, String text) =>
      ParticipantSummaryModel(
        participantId: userId,
        feedback: text,
        cefrLevel: 'A2',
        superlatives: const [],
      );

  void setCard(Room room, String userId, ActivitySummaryModel model) =>
      setState(
        room,
        PangeaEventTypes.activitySummary,
        ActivitySummaryStateKeys.card(userId),
        model.toJson(),
        sender: bot,
      );

  ActivitySummaryModel card(String userId, String text) => ActivitySummaryModel(
    summary: ActivitySummaryResponseModel(
      participants: [feedback(userId, text)],
      summary: '',
    ),
  );

  /// Opens the room's summary and finished-status bar; returns the strings to
  /// look for.
  Future<L10n> pump(WidgetTester tester, Room room) async {
    final controller = ActivityChatController(
      userID: learner,
      room: room,
      inputFocus: FocusNode(),
    );
    addTearDown(() => tester.runAsync(controller.dispose));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                ActivitySummaryCards(activityController: controller),
                ActivityFinishedStatusMessage(activityController: controller),
              ],
            ),
          ),
        ),
      ),
    );
    // Two frames, not pumpAndSettle: the localization delegates resolve a
    // frame later, and a loading card's spinner never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return L10n.of(tester.element(find.byType(ActivitySummaryCards)));
  }

  testWidgets('a learner who finishes first sees their card while they wait', (
    tester,
  ) async {
    final room = activityRoom();
    setCard(room, learner, card(learner, 'You ordered well.'));

    final l10n = await pump(tester, room);

    expect(find.text('You ordered well.'), findsOneWidget);
    expect(find.text(l10n.waitingForOthersToFinish), findsOneWidget);
    // Only the whole room finishing is "all finished".
    expect(find.text(l10n.activityFinishedMessage), findsNothing);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
  });

  testWidgets('their card loads in the chat, not in the bar', (tester) async {
    final room = activityRoom();
    // The loading marker's deadline, which reads the real clock, is close.
    setCard(
      room,
      learner,
      ActivitySummaryModel(
        requestedAt: DateTime.now().subtract(
          ActivitySummaryModel.requestTimeout -
              const Duration(milliseconds: 300),
        ),
      ),
    );

    final l10n = await pump(tester, room);

    expect(find.text(l10n.generatingSummary), findsOneWidget);
    expect(find.text(l10n.waitingForOthersToFinish), findsOneWidget);

    // A bot that never answers ends in the error, not an endless spinner.
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(l10n.generatingSummary), findsNothing);
    expect(find.text(l10n.activitySummaryError), findsOneWidget);
  });

  testWidgets('a failed card offers a retry where the card would be', (
    tester,
  ) async {
    final room = activityRoom();
    setCard(room, learner, ActivitySummaryModel(errorAt: DateTime.now()));

    final l10n = await pump(tester, room);

    expect(find.text(l10n.activitySummaryError), findsOneWidget);
    expect(find.text(l10n.requestSummaries), findsOneWidget);
    expect(find.text(l10n.waitingForOthersToFinish), findsOneWidget);
  });

  testWidgets('a learner still playing sees no cards', (tester) async {
    final room = activityRoom(learnerDone: false, coursemateDone: true);
    setCard(room, coursemate, card(coursemate, 'You served well.'));

    final l10n = await pump(tester, room);

    expect(find.text('You served well.'), findsNothing);
    expect(find.text(l10n.waitingForOthersToFinish), findsNothing);
  });

  testWidgets('once the activity has finished, the bar steps aside for "all '
      'finished"', (tester) async {
    final room = activityRoom(botPartner: true);
    setCard(room, learner, card(learner, 'You ordered well.'));

    final l10n = await pump(tester, room);

    expect(find.text(l10n.activityFinishedMessage), findsOneWidget);
    expect(find.text(l10n.waitingForOthersToFinish), findsNothing);
    expect(find.text('You ordered well.'), findsOneWidget);
  });

  testWidgets('a room summarized before per-learner cards shows its group '
      'text', (tester) async {
    final room = activityRoom(botPartner: true);
    setState(
      room,
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.canonical,
      ActivitySummaryModel(
        summary: ActivitySummaryResponseModel(
          participants: [feedback(learner, 'You ordered well.')],
          summary: 'A friendly chat at the counter.',
        ),
      ).toJson(),
      sender: bot,
    );

    await pump(tester, room);

    expect(find.text('A friendly chat at the counter.'), findsOneWidget);
    expect(find.text('You ordered well.'), findsOneWidget);
  });
}

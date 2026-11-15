import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/overlay/any_state_holder.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_stats_menu.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../activity_session_fixtures.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// A discussion uses the roleplay goal header (#9647), with its questions as
/// the goals, and never offers "End for all": each student ends only their
/// own seat. "I'm done" is there only for someone holding a seat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const me = testSessionUserId;
  const classmate = '@classmate:fakeServer.notExisting';

  late Client client;

  setUpAll(() async {
    dotenv.testLoad(fileInput: 'BOT_NAME=$testDiscussionBotId');
    final tempDir = await Directory.systemTemp.createTemp('discussion_header');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  setUp(() async {
    client = await getTestClient();
    MatrixState.pangeaController = FakePangeaController(client: client);
    MatrixState.pAnyState = PangeaAnyState();
  });

  tearDown(() async {
    await client.dispose();
  });

  /// The header for [room], opened.
  Future<L10n> pumpOpenHeader(WidgetTester tester, Room room) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390.0, 900.0);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          // The chat view stacks the header over the timeline.
          body: Stack(
            children: [
              ActivityStatsMenu(
                visibilityNotifier: ValueNotifier(true),
                setShowDropdown: (_) {},
                activeGoalNotifier: ValueNotifier<ActivityRoleGoal?>(null),
                room: room,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return L10n.of(tester.element(find.byType(Scaffold)));
  }

  testWidgets('an admin holding a seat gets "I\'m done" but no End for '
      'all', (tester) async {
    final room = discussionRoom(
      client,
      seats: [discussionSeat(me), discussionSeat(classmate)],
      powerLevels: {me: 100, testDiscussionBotId: 100},
    );
    final l10n = await pumpOpenHeader(tester, room);

    expect(find.text('goal 1'), findsWidgets);
    expect(find.text(l10n.completeActivityButton), findsOneWidget);
    expect(find.text(l10n.endForAll), findsNothing);
  });

  testWidgets('an admin watching without a seat gets no action at all', (
    tester,
  ) async {
    final room = discussionRoom(
      client,
      seats: [discussionSeat(classmate)],
      powerLevels: {me: 100, testDiscussionBotId: 100},
    );
    final l10n = await pumpOpenHeader(tester, room);

    expect(find.text(l10n.completeActivityButton), findsNothing);
    expect(find.text(l10n.endForAll), findsNothing);
  });

  testWidgets('a roleplay\'s admin still gets End for all', (tester) async {
    final room = activitySessionRoom(
      client,
      roles: {
        'r1': ActivityRoleModel(id: 'r1', userId: me, role: 'Fan'),
        'r2': ActivityRoleModel(id: 'r2', userId: classmate, role: 'V'),
      },
    );
    room.setState(
      activitySessionStateEvent(
        room,
        type: EventTypes.RoomPowerLevels,
        content: {
          'users': {me: 100},
          'users_default': 0,
          // Open role and summary state: what makes a roleplay room show
          // its activity UI.
          'events': {
            PangeaEventTypes.activityRole: 0,
            PangeaEventTypes.activitySummary: 0,
          },
        },
      ),
    );
    final l10n = await pumpOpenHeader(tester, room);

    expect(find.text(l10n.endForAll), findsOneWidget);
  });
}

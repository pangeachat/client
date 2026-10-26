import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item.dart';
import 'package:fluffychat/routes/world/saved_activities_client_extension.dart';
import 'package:fluffychat/widgets/completed_stamp.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../activity_session_fixtures.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// A live session's Chats row wears the completed stamp when the learner is
/// replaying an activity they have already saved a session of.
void main() {
  late Client client;

  setUpAll(() {
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  /// A saved (archived) earlier session of [activityId] in the learner's rooms.
  Room savedSession(String activityId, {required String roomId}) {
    final room = activitySessionRoom(
      client,
      roomId: roomId,
      activityId: activityId,
      roles: {
        'r1': ActivityRoleModel(
          id: 'r1',
          userId: testSessionUserId,
          role: 'Fan',
          finishedAt: DateTime.utc(2026, 1, 1),
          archivedAt: DateTime.utc(2026, 1, 1),
        ),
      },
    );
    client.rooms.add(room);
    return room;
  }

  Future<void> pumpRow(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: 380, child: ChatListItem(room, onTap: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('the client knows which activities have a saved session', () {
    final saved = savedSession(testSessionActivityId, roomId: '!old:x');
    client.rooms.add(activitySessionRoom(client, activityId: 'other'));

    expect(saved.hasArchivedActivity, isTrue);
    expect(client.hasSavedSessionOf(testSessionActivityId), isTrue);
    expect(client.hasSavedSessionOf('other'), isFalse);
  });

  testWidgets('a replayed activity\'s row wears the completed stamp', (
    tester,
  ) async {
    savedSession(testSessionActivityId, roomId: '!old:x');
    final live = activitySessionRoom(client);
    client.rooms.add(live);

    await pumpRow(tester, live);
    expect(find.byType(CompletedStamp), findsOneWidget);
  });

  testWidgets('a first play of an activity wears no stamp', (tester) async {
    savedSession('another-activity', roomId: '!old:x');
    final live = activitySessionRoom(client);
    client.rooms.add(live);

    await pumpRow(tester, live);
    expect(find.byType(CompletedStamp), findsNothing);
  });
}

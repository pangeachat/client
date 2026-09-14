import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/activity_participant_row.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item_subtitle.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import '../activity_session_fixtures.dart';
import '../get_test_client.dart';

/// #8684 — a session still filling seats shows, under its Chats-tile title,
/// the same hourglass + participant row its world-map pending card shows, from
/// the same room-state pair, so the tile and the card cannot drift. Once every
/// seat is claimed the tile flips to the ongoing-active body (preview + stars)
/// and the hourglass goes away.
void main() {
  late Client client;

  // Avatar reads the bot name out of the environment to spot the bot's own
  // avatar, and an unloaded dotenv throws before it can paint.
  setUpAll(() => dotenv.testLoad(mergeWith: {}));

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Future<void> pumpSubtitle(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ChatListItemSubtitle(room: room, style: const TextStyle()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a not-started session shows the hourglass and its open seats', (
    tester,
  ) async {
    // No seat claimed on the two-role plan: two open person-silhouette seats.
    await pumpSubtitle(tester, activitySessionRoom(client));
    expect(find.byIcon(Icons.hourglass_bottom), findsOneWidget);
    expect(find.byIcon(Icons.person), findsNWidgets(2));
    expect(find.byType(ActivityStarRow), findsNothing);
  });

  testWidgets(
    'the row is the map card\'s own widget, at the active body\'s avatar size '
    'and in the map\'s ongoing accent',
    (tester) async {
      await pumpSubtitle(tester, activitySessionRoom(client));
      final row = tester.widget<ActivityParticipantRow>(
        find.byType(ActivityParticipantRow),
      );
      expect(row.avatarSize, 24);
      expect(row.accent, AppConfig.primaryColor);
      expect(row.participants, isEmpty);
      expect(row.openSlots, 2);
    },
  );

  testWidgets('a full session shows the active body, not the hourglass', (
    tester,
  ) async {
    final room = activitySessionRoom(
      client,
      roles: {
        'r1': ActivityRoleModel(
          id: 'r1',
          userId: testSessionUserId,
          role: 'Fan',
        ),
        'r2': ActivityRoleModel(
          id: 'r2',
          userId: '@other:fakeServer.notExisting',
          role: 'Visitor',
        ),
      },
    );
    await pumpSubtitle(tester, room);
    expect(find.byIcon(Icons.hourglass_bottom), findsNothing);
    expect(find.byType(ActivityParticipantRow), findsNothing);
    expect(find.byType(ActivityStarRow), findsOneWidget);
  });
}

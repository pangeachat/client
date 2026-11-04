import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_summary_goals.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'activity_session_fixtures.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #9696 — the finished activity's summary shows the learner the XP their
/// goal header showed during play, goals included, on their own card only;
/// the session's row on the Learning Objectives page shows the same figure
/// (activity-session.instructions.md, "The summary"; activities.instructions.md,
/// "The Learning Objectives page").
void main() {
  late Client client;

  const otherId = '@alice:fakeServer.notExisting';

  /// 30 XP credited to the room, plus 50 for each of the learner's two goals.
  const sessionXp = '130 XP';

  void learn(String langCode) =>
      MatrixState.pangeaController = FakePangeaController(
        userL2: LanguageModel(langCode: langCode, displayName: langCode),
      );

  setUpAll(() {
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
  });

  setUp(() async {
    // The fixture's activity is in Spanish.
    learn('es');
    client = await getTestClient();
    MissionXpCache.instance.seed(xpByRoom: {testSessionRoomId: 30});
  });
  tearDown(() async {
    MissionXpCache.instance.seed();
    await client.dispose();
  });

  /// The learner played the Fan and earned two goals; Alice played the
  /// Visitor and earned one. The saved summary, which the Learning
  /// Objectives row needs before it shows numbers, counts the learner's word
  /// uses (10), which is not the XP the session paid.
  Room session() {
    final room = activitySessionRoom(
      client,
      roles: {
        'r1': ActivityRoleModel(
          id: 'r1',
          userId: testSessionUserId,
          role: 'Fan',
        ),
        'r2': ActivityRoleModel(id: 'r2', userId: otherId, role: 'Visitor'),
      },
      awarded: {
        'r1': ['slug-1', 'slug-2'],
        'r2': ['slug-4'],
      },
    );
    room.setState(
      activitySessionStateEvent(
        room,
        type: PangeaEventTypes.activitySummary,
        stateKey: 'en',
        content: {
          'summary': {
            'summary': 'A chat about the match.',
            'participants': [
              {
                'participant_id': testSessionUserId,
                'feedback': 'Nicely done.',
                'cefr_level': 'A1',
                'superlatives': [],
              },
            ],
          },
          'analytics': {
            testSessionUserId: [
              {'lemma': 'gol', 'type': 'vocab', 'cat': 'n', 'times_used': 10},
            ],
          },
        },
      ),
    );
    return room;
  }

  /// The summary's goal list for the participant holding [roleId].
  ActivitySummaryGoals goals(Room room, String roleId, String participantId) =>
      ActivitySummaryGoals(
        room: room,
        role: room.activityPlan!.roles[roleId]!,
        participantId: participantId,
      );

  Future<void> pump(WidgetTester tester, List<Widget> children) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: Column(children: children)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the learner\'s own card shows the XP their goal header showed', (
    tester,
  ) async {
    await pump(tester, [goals(session(), 'r1', testSessionUserId)]);

    expect(find.text(sessionXp), findsOneWidget);
    expect(find.text('goal 1'), findsOneWidget);
  });

  testWidgets('another player\'s card shows their goals and no XP', (
    tester,
  ) async {
    await pump(tester, [goals(session(), 'r2', otherId)]);

    expect(find.text('goal 4'), findsOneWidget);
    expect(find.textContaining('XP'), findsNothing);
  });

  testWidgets(
    'a session outside the learner\'s current language shows no XP, as its '
    'header showed none',
    (tester) async {
      learn('fr');
      await pump(tester, [goals(session(), 'r1', testSessionUserId)]);

      expect(find.text('goal 1'), findsOneWidget);
      expect(find.textContaining('XP'), findsNothing);
    },
  );

  testWidgets('the session\'s Learning Objectives row shows the same figure', (
    tester,
  ) async {
    final room = session();
    await pump(tester, [
      goals(room, 'r1', testSessionUserId),
      AnalyticsActivityItem(room: room),
    ]);

    expect(find.text(sessionXp), findsNWidgets(2));
  });
}

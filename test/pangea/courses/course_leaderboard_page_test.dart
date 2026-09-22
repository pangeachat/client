import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/chat_details/course_leaderboard_page.dart';
import 'package:fluffychat/routes/chat/chat_details/leaderboard_row.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}

/// Coverage for #9212's full page (course-leaderboard.instructions.md): the
/// podium, then fourth place onward as tiles in two columns on a wide page
/// and one on a narrow one, then the pending members as cards, then invite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late SharedPreferences store;

  const userId = '@test:fakeServer.notExisting';
  const language = 'es';

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('leaderboard_page');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': '@bot:example.org',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  void setStateEvent(
    Room room,
    String type, {
    required Map<String, Object?> content,
    String stateKey = '',
    String? senderId,
  }) => room.setState(
    Event(
      type: type,
      content: content,
      stateKey: stateKey,
      senderId: senderId ?? userId,
      eventId: '\$$type$stateKey',
      originServerTs: DateTime.now(),
      room: room,
    ),
  );

  String memberId(int i) => '@member$i:fakeServer.notExisting';

  /// A course the viewer administers with [members] joined (the viewer
  /// included), [invited] invitees and [knocking] knockers; Member i holds
  /// i stars, so the ranking runs Member 5, 4, 3, 2, 1, Testy.
  Room courseRoom({required int members, int invited = 0, int knocking = 0}) {
    MatrixState.pangeaController = FakePangeaController(
      analyticsProfiles: {
        for (var i = 1; i < members; i++)
          memberId(i): AnalyticsProfileModel(
            targetLanguage: language,
            languageAnalytics: {
              language: LanguageAnalyticsProfileEntry(1, 0, stars: i),
            },
          ),
      },
    );
    final room = Room(
      id: '!course:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
      summary: RoomSummary.fromJson({
        'm.joined_member_count': members,
        'm.invited_member_count': invited,
        'm.heroes': <String>[],
      }),
    );
    setStateEvent(room, EventTypes.RoomCreate, content: {'type': 'm.space'});
    setStateEvent(
      room,
      PangeaEventTypes.coursePlan,
      content: {'uuid': 'plan', 'l2': language},
    );
    setStateEvent(
      room,
      EventTypes.RoomPowerLevels,
      content: {
        ...RoomDefaults.defaultPowerLevelsContent(),
        'users': {userId: SpaceConstants.powerLevelOfAdmin},
      },
    );
    void member(String id, String name, String membership) => setStateEvent(
      room,
      EventTypes.RoomMember,
      content: {'membership': membership, 'displayname': name},
      stateKey: id,
      senderId: membership == 'join' ? id : userId,
    );
    member(userId, 'Testy', 'join');
    for (var i = 1; i < members; i++) {
      member(memberId(i), 'Member $i', 'join');
    }
    for (var i = 1; i <= invited; i++) {
      member('@invitee$i:fakeServer.notExisting', 'Invitee $i', 'invite');
    }
    for (var i = 1; i <= knocking; i++) {
      member('@knocker$i:fakeServer.notExisting', 'Knocker $i', 'knock');
    }
    return room;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    Room room, {
    required double width,
  }) async {
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: width,
                child: CourseLeaderboardPage(room: room),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(seconds: 10));
  }

  List<int> tileRanks(WidgetTester tester) => tester
      .widgetList<LeaderboardTile>(find.byType(LeaderboardTile))
      .map((t) => t.entry.rank)
      .toList();

  testWidgets('podium, then tiles in two columns on a wide page', (
    tester,
  ) async {
    await pumpPage(
      tester,
      courseRoom(members: 6),
      width: CourseLeaderboardPage.twoColumnMinWidth,
    );

    expect(find.byType(LeaderboardRow), findsNWidgets(3));
    expect(tileRanks(tester), [4, 5, 6]);
    // Ranks 4 and 5 share a line; 6 starts the next.
    final tiles = find.byType(LeaderboardTile);
    expect(
      tester.getTopLeft(tiles.at(0)).dy,
      tester.getTopLeft(tiles.at(1)).dy,
    );
    expect(
      tester.getTopLeft(tiles.at(2)).dy,
      greaterThan(tester.getTopLeft(tiles.at(1)).dy),
    );
    expect(
      tester.getTopLeft(tiles.at(0)).dy,
      greaterThan(tester.getBottomLeft(find.byType(LeaderboardRow).last).dy),
    );

    await drain(tester);
  });

  testWidgets('one column on a narrow page', (tester) async {
    await pumpPage(
      tester,
      courseRoom(members: 6),
      width: CourseLeaderboardPage.twoColumnMinWidth - 1,
    );

    final tiles = find.byType(LeaderboardTile);
    expect(
      tester.getTopLeft(tiles.at(1)).dy,
      greaterThan(tester.getTopLeft(tiles.at(0)).dy),
    );

    await drain(tester);
  });

  testWidgets(
    'pending members sit below the ranking, unranked, before invite',
    (tester) async {
      await pumpPage(
        tester,
        courseRoom(members: 2, invited: 1, knocking: 1),
        width: 400,
      );

      expect(find.byType(LeaderboardRow), findsNWidgets(2));
      expect(find.byType(LeaderboardTile), findsNothing);
      // The admin line's card, then the two pending cards.
      final cards = tester
          .widgetList<ParticipantCard>(find.byType(ParticipantCard))
          .toList();
      expect(cards.map((c) => c.user.displayName), [
        'Testy',
        'Invitee 1',
        'Knocker 1',
      ]);
      expect(cards.every((c) => !c.showStats), isTrue);
      expect(find.text('Invited'), findsOneWidget);
      expect(find.text('Knocking'), findsOneWidget);

      final lastRow = tester.getBottomLeft(find.byType(LeaderboardRow).last).dy;
      final invitee = tester.getTopLeft(find.text('Invitee 1')).dy;
      final invite = tester.getTopLeft(find.byType(LeaderboardInviteRow)).dy;
      expect(invitee, greaterThan(lastRow));
      expect(invite, greaterThan(invitee));

      await drain(tester);
    },
  );
}

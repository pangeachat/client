import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_leaderboard_preview.dart';
import 'package:fluffychat/routes/chat/chat_details/leaderboard_row.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// Skips `initMatrix()` — the member-actions menu on each row only wants
/// `Matrix.of(context)`.
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

/// Coverage for #9212, the course page's Leaderboard section
/// (course-leaderboard.instructions.md): the admin line over the podium, the
/// ranking by stars, "See all" only when the full page holds more, the invite
/// row under a lone member, the bot's absence, and — carried over from #8744
/// and #9154 — invite in the header whenever this user may invite, and one
/// Tab stop with the arrow keys moving between cards and rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late SharedPreferences store;

  const userId = '@test:fakeServer.notExisting';
  const botId = '@bot:example.org';
  const language = 'es';

  // ParticipantCard.compactWidth 80 + 8 spacing: four admin cards fit 360.
  const width = 360.0;

  setUpAll(() async {
    // `Avatar` resolves the bot name from the environment at build time, which
    // reads GetStorage (path_provider-backed) and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('course_leaderboard');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': botId,
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
  });

  setUp(() async {
    client = await getTestClient();
    // The member loader ranks on these; a test that wants stars sets its own.
    MatrixState.pangeaController = FakePangeaController();
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

  /// A course space in [language] that the viewer administers, holding
  /// [members] joined members (the viewer included), plus any [invited] and
  /// the bot when [withBot]. The joined-member summary matches the member
  /// state so the SDK counts the list complete and no participant fetch runs.
  Room courseRoom({
    required int members,
    int invited = 0,
    bool withBot = false,
  }) {
    final room = Room(
      id: '!course:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
      summary: RoomSummary.fromJson({
        'm.joined_member_count': members + (withBot ? 1 : 0),
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
    void join(String id, String name) => setStateEvent(
      room,
      EventTypes.RoomMember,
      content: {'membership': 'join', 'displayname': name},
      stateKey: id,
      senderId: id,
    );
    join(userId, 'Testy');
    for (var i = 1; i < members; i++) {
      join(memberId(i), 'Member $i');
    }
    if (withBot) join(botId, 'Pangea Bot');
    for (var i = 1; i <= invited; i++) {
      setStateEvent(
        room,
        EventTypes.RoomMember,
        content: {'membership': 'invite', 'displayname': 'Invitee $i'},
        stateKey: '@invitee$i:fakeServer.notExisting',
      );
    }
    return room;
  }

  AnalyticsProfileModel profile({required int stars, int? level}) =>
      AnalyticsProfileModel(
        targetLanguage: language,
        languageAnalytics: {
          language: LanguageAnalyticsProfileEntry(level ?? 0, 0, stars: stars),
        },
      );

  var onInviteCalls = 0;

  Future<void> pumpPreview(WidgetTester tester, Room room) async {
    onInviteCalls = 0;
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
                child: CourseLeaderboardPreview(
                  room: room,
                  onShowAll: () {},
                  onInvite: () => onInviteCalls++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so nothing is in the
    // tree until localizations finish loading — and the profiles load after.
    await tester.pumpAndSettle();
  }

  /// The member cards start presence and avatar work that outlives the tree.
  /// Tear the tree down and let both finish — a pending timer fails the
  /// binding's invariants, and a presence read still in flight hits the
  /// client's database after `tearDown` closes it.
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(seconds: 10));
  }

  /// The invite control is icon-only, so it is found by its tooltip — which
  /// is also its accessible name.
  Finder inviteShortcut() => find.byTooltip('Invite');

  /// The podium's rows, top to bottom, by the member each names.
  List<String> podiumNames(WidgetTester tester) => tester
      .widgetList<LeaderboardRow>(find.byType(LeaderboardRow))
      .map((row) => row.entry.user.displayName!)
      .toList();

  testWidgets('three members: the admin line, three podium rows, no See all', (
    tester,
  ) async {
    await pumpPreview(tester, courseRoom(members: 3));

    // The admin line holds the one admin, without stats.
    final adminCards = tester.widgetList<ParticipantCard>(
      find.byType(ParticipantCard),
    );
    expect(adminCards.map((c) => c.user.id), [userId]);
    expect(adminCards.single.showStats, isFalse);
    // The badge is on the card, and again on the admin's own ranked row.
    expect(
      find.descendant(
        of: find.byType(ParticipantCard),
        matching: find.text('Admin'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(LeaderboardRow),
        matching: find.text('Admin'),
      ),
      findsOneWidget,
    );

    expect(find.byType(LeaderboardRow), findsNWidgets(3));
    expect(find.byType(LeaderboardInviteRow), findsNothing);
    expect(inviteShortcut(), findsOneWidget);
    // The full page would only repeat these same three rows.
    expect(find.text('See all'), findsNothing);

    await drain(tester);
  });

  testWidgets('rows rank by stars, then level, and show both', (tester) async {
    MatrixState.pangeaController = FakePangeaController(
      analyticsProfiles: {
        userId: profile(stars: 5, level: 3),
        memberId(1): profile(stars: 8, level: 2),
        memberId(2): profile(stars: 8, level: 7),
        memberId(3): profile(stars: 10, level: 1),
      },
    );
    await pumpPreview(tester, courseRoom(members: 4));

    expect(podiumNames(tester), ['Member 3', 'Member 2', 'Member 1']);
    expect(find.text('10'), findsOneWidget);
    // One node per row, the level's own node folded in.
    final handle = tester.ensureSemantics();
    final first = tester.semantics
        .simulatedAccessibilityTraversal()
        .firstWhere((n) => n.getSemanticsData().label.contains('Member 3'))
        .getSemanticsData();
    expect(first.label, contains('Rank 1'));
    expect(first.label, contains('Stars earned in'));
    expect(first.label, contains(': 10'));
    expect(first.label, contains('Level 1'));
    handle.dispose();

    await drain(tester);
  });

  testWidgets('a fourth ranked member adds See all', (tester) async {
    await pumpPreview(tester, courseRoom(members: 4));

    expect(find.byType(LeaderboardRow), findsNWidgets(3));
    expect(find.text('See all'), findsOneWidget);
    expect(inviteShortcut(), findsOneWidget);

    await drain(tester);
  });

  testWidgets('a pending member adds See all', (tester) async {
    await pumpPreview(tester, courseRoom(members: 3, invited: 1));

    // The invitee is on the full page only, so the preview offers it.
    expect(find.text('Invitee 1'), findsNothing);
    expect(find.text('See all'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('a lone member gets an invite row in second place', (
    tester,
  ) async {
    await pumpPreview(tester, courseRoom(members: 1));

    expect(podiumNames(tester), ['Testy']);
    final inviteRow = find.byType(LeaderboardInviteRow);
    expect(inviteRow, findsOneWidget);
    expect(
      tester.getTopLeft(inviteRow).dy,
      greaterThan(tester.getBottomLeft(find.byType(LeaderboardRow)).dy),
    );
    expect(find.text('See all'), findsNothing);

    await tester.tap(inviteRow);
    expect(onInviteCalls, 1);

    await drain(tester);
  });

  testWidgets('the bot is neither an admin nor ranked', (tester) async {
    await pumpPreview(tester, courseRoom(members: 2, withBot: true));

    expect(podiumNames(tester), isNot(contains('Pangea Bot')));
    expect(find.byType(LeaderboardRow), findsNWidgets(2));
    expect(find.byType(ParticipantCard), findsOneWidget);

    await drain(tester);
  });

  testWidgets(
    'the section is one Tab stop; each row is one focusable button (#9154)',
    (tester) async {
      MatrixState.pangeaController = FakePangeaController(
        analyticsProfiles: {
          memberId(1): profile(stars: 2),
          memberId(2): profile(stars: 1),
        },
      );
      final handle = tester.ensureSemantics();
      await pumpPreview(tester, courseRoom(members: 3));

      /// The label of the node assistive tech is on.
      String focusedLabel() => tester.semantics
          .simulatedAccessibilityTraversal()
          .where((n) => n.flagsCollection.isFocused == Tristate.isTrue)
          .map((n) => n.getSemanticsData().label)
          .join('|');

      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }

      // Tab: the header's invite shortcut, then the admin line's card.
      await press(LogicalKeyboardKey.tab);
      await press(LogicalKeyboardKey.tab);
      expect(focusedLabel(), contains('Testy'));
      expect(focusedLabel(), isNot(contains('Rank')));

      // The arrow keys walk from the admin line down the podium.
      await press(LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), contains('Rank 1'));
      expect(focusedLabel(), contains('Member 1'));
      await press(LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), contains('Rank 2'));
      await press(LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), contains('Rank 1'));

      // Tab leaves the section in one press, past the rows not visited.
      await press(LogicalKeyboardKey.tab);
      expect(focusedLabel(), isNot(contains('Rank')));

      // Each row is one node: a button that takes focus and a tap, named for
      // its rank and member.
      for (final rank in [1, 2, 3]) {
        final nodes = tester.semantics
            .simulatedAccessibilityTraversal()
            .where((n) => n.getSemanticsData().label.contains('Rank $rank'))
            .toList();
        expect(nodes, hasLength(1), reason: 'rank $rank is one node');
        final data = nodes.single.getSemanticsData();
        expect(nodes.single.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.focus), isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
      }

      handle.dispose();
      await drain(tester);
    },
  );
}

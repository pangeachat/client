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

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_participants_preview.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/users/course_member_stats.dart';
import '../audio_players_stub.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';
import '../settle_participants.dart';

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

/// Coverage for #9776, the course page's Participants section
/// (course-participants.instructions.md): one line of cards without stats,
/// admins first, "See all" only when the full page holds more, the bot's
/// absence, and — carried over from #8744 and #9154 — invite in the header
/// whenever this user may invite, and one Tab stop with the arrow keys moving
/// between cards.
void main() {
  tearDownAll(AudioPlayersStub.uninstall);
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late SharedPreferences store;

  const userId = '@test:fakeServer.notExisting';
  const botId = '@bot:example.org';
  const language = 'es';

  // ParticipantCard.width 100 + 8 spacing: three cards fit 340.
  const width = 340.0;

  setUpAll(() async {
    AudioPlayersStub.install();
    // `Avatar` resolves the bot name from the environment at build time, which
    // reads GetStorage (path_provider-backed) and dotenv.
    final tempDir = await Directory.systemTemp.createTemp(
      'course_participants',
    );
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
  /// [members] joined members (the viewer, the one admin, included), plus any
  /// [invited] and the bot when [withBot]. The joined-member summary matches the member
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

  var onInviteCalls = 0;

  Future<void> pumpPreview(WidgetTester tester, Room room) async {
    onInviteCalls = 0;
    cacheMemberPresence(room);
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
                child: CourseParticipantsPreview(
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
    await settle(tester, find.byType(CourseParticipantsPreview));
  }

  /// The invite control is icon-only, so it is found by its tooltip — which
  /// is also its accessible name.
  Finder inviteShortcut() => find.byTooltip('Invite');

  List<ParticipantCard> cards(WidgetTester tester) =>
      tester.widgetList<ParticipantCard>(find.byType(ParticipantCard)).toList();

  testWidgets('admins first, then members by name, with no stats or rings', (
    tester,
  ) async {
    await pumpPreview(tester, courseRoom(members: 3));

    expect(cards(tester).map((c) => c.user.displayName), [
      'Testy',
      'Member 1',
      'Member 2',
    ]);
    expect(
      cards(tester).every((c) => !c.showStats && c.gradient == null),
      isTrue,
    );
    expect(find.byType(CourseMemberStats), findsNothing);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Participants'), findsOneWidget);
    expect(inviteShortcut(), findsOneWidget);
    expect(find.text('See all'), findsNothing);
  });

  testWidgets('the section does not load member analytics profiles', (
    tester,
  ) async {
    await pumpPreview(tester, courseRoom(members: 3));

    expect(
      tester
          .widget<LoadParticipantsBuilder>(find.byType(LoadParticipantsBuilder))
          .loadProfiles,
      isFalse,
    );
  });

  testWidgets('more members than fit are cut, and See all appears', (
    tester,
  ) async {
    await pumpPreview(tester, courseRoom(members: 4));

    expect(find.byType(ParticipantCard), findsNWidgets(3));
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('a pending member adds See all', (tester) async {
    await pumpPreview(tester, courseRoom(members: 2, invited: 1));

    // The invitee is on the full page only, so the preview offers it.
    expect(find.text('Invitee 1'), findsNothing);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('the header invite shortcut opens the invite flow', (
    tester,
  ) async {
    await pumpPreview(tester, courseRoom(members: 1));

    await tester.tap(inviteShortcut());
    await tester.pumpAndSettle();
    expect(onInviteCalls, 1);
  });

  // CLIENT-F0M / F1F (#9806). The course page still builds through a sign-out
  // (#9019), and the SDK's `canInvite` needs `client.userID!`.
  testWidgets('after a sign-out the preview rebuilds without invite', (
    tester,
  ) async {
    final room = courseRoom(members: 2);
    await pumpPreview(tester, room);
    expect(inviteShortcut(), findsOneWidget, reason: 'precondition');

    await tester.runAsync(client.clear);
    expect(client.userID, isNull, reason: 'precondition');
    await pumpPreview(tester, room);

    expect(tester.takeException(), isNull);
    expect(inviteShortcut(), findsNothing);
  });

  testWidgets('the bot is not listed', (tester) async {
    await pumpPreview(tester, courseRoom(members: 2, withBot: true));

    expect(cards(tester).map((c) => c.user.displayName), ['Testy', 'Member 1']);
  });

  testWidgets('the line is one Tab stop with the arrow keys inside (#9154)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpPreview(tester, courseRoom(members: 3));

    String focusedLabel() => tester.semantics
        .simulatedAccessibilityTraversal()
        .where((n) => n.flagsCollection.isFocused == Tristate.isTrue)
        .map((n) => n.getSemanticsData().label)
        .join('|');

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    // Tab: the header's invite shortcut, then the first card.
    await press(LogicalKeyboardKey.tab);
    await press(LogicalKeyboardKey.tab);
    expect(focusedLabel(), contains('Testy'));

    await press(LogicalKeyboardKey.arrowRight);
    expect(focusedLabel(), contains('Member 1'));
    await press(LogicalKeyboardKey.arrowLeft);
    expect(focusedLabel(), contains('Testy'));

    // Tab leaves the line in one press, past the cards not visited.
    await press(LogicalKeyboardKey.tab);
    expect(focusedLabel(), isNot(contains('Member')));

    // Each card is one node: a button that takes focus and a tap.
    final nodes = tester.semantics
        .simulatedAccessibilityTraversal()
        .where((n) => n.getSemanticsData().label.contains('Member 1'))
        .toList();
    expect(nodes, hasLength(1));
    final data = nodes.single.getSemanticsData();
    expect(nodes.single.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.focus), isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    handle.dispose();
  });
}

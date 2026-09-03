import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_participants_preview.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// Skips `initMatrix()` — the member-actions menu on each card only wants
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

/// Coverage for #8744: the Participants header carries invite whenever this
/// user may invite — a section showing every member is exactly the one whose
/// useful next step is inviting more, and a full one still is — while "See
/// all" appears only when the card line was truncated, since a subpage
/// repeating the same cards is not worth offering.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late SharedPreferences store;

  const userId = '@test:fakeServer.notExisting';

  // ParticipantCard.width 100 + 8 spacing: three whole cards fit 360.
  const width = 360.0;
  const fits = 3;

  setUpAll(() async {
    // `Avatar` resolves the bot name from the environment at build time, which
    // reads GetStorage (path_provider-backed) and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('course_members');
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
    // The member-actions menu reads the static controller while building its
    // profile card (level and about-me).
    MatrixState.pangeaController = FakePangeaController();
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

  /// A course space the viewer administers, holding [members] joined members
  /// (the viewer included). The joined-member summary matches the member state
  /// so the SDK counts the list complete and no participant fetch runs.
  Room courseRoom({required int members}) {
    final room = Room(
      id: '!course:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
      summary: RoomSummary.fromJson({
        'm.joined_member_count': members,
        'm.invited_member_count': 0,
        'm.heroes': <String>[],
      }),
    );
    setStateEvent(room, EventTypes.RoomCreate, content: {'type': 'm.space'});
    setStateEvent(
      room,
      EventTypes.RoomPowerLevels,
      content: {
        ...RoomDefaults.defaultPowerLevelsContent(),
        'users': {userId: SpaceConstants.powerLevelOfAdmin},
      },
    );
    setStateEvent(
      room,
      EventTypes.RoomMember,
      content: {'membership': 'join', 'displayname': 'Testy'},
      stateKey: userId,
      senderId: userId,
    );
    for (var i = 1; i < members; i++) {
      final memberId = '@member$i:fakeServer.notExisting';
      setStateEvent(
        room,
        EventTypes.RoomMember,
        content: {'membership': 'join', 'displayname': 'Member $i'},
        stateKey: memberId,
        senderId: memberId,
      );
    }
    return room;
  }

  Future<void> pumpPreview(WidgetTester tester, Room room) async {
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
                  onInvite: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so nothing is in the
    // tree until localizations finish loading.
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

  /// The invite control is icon-only now, so it is found by its tooltip —
  /// which is also its accessible name.
  Finder inviteButton() => find.byTooltip('Invite');

  testWidgets('a section that fits every member offers invite, not See all', (
    tester,
  ) async {
    await pumpPreview(tester, courseRoom(members: fits));

    expect(find.byType(ParticipantCard), findsNWidgets(fits));
    expect(inviteButton(), findsOneWidget);
    // Nothing was cut, so the subpage would only repeat these same cards.
    expect(find.text('See all'), findsNothing);

    await drain(tester);
  });

  testWidgets('a truncated section keeps invite and adds See all', (
    tester,
  ) async {
    await pumpPreview(tester, courseRoom(members: fits + 3));

    // Only the cards that fit the line render; the rest are on the subpage.
    expect(find.byType(ParticipantCard), findsNWidgets(fits));
    expect(find.text('See all'), findsOneWidget);
    expect(inviteButton(), findsOneWidget);

    await drain(tester);
  });
}

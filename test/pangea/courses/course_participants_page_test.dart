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
import 'package:fluffychat/routes/chat/chat_details/course_participants_page.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';
import 'package:fluffychat/routes/chat/chat_details/room_participants_widget.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/users/course_member_stats.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';
import '../settle_participants.dart';

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

/// Coverage for #9776's full page (course-participants.instructions.md): every
/// member as a card without stats, admins first, pending members last, then
/// the invite tile.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late SharedPreferences store;

  const userId = '@test:fakeServer.notExisting';

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('participants_page');
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

  /// A course the viewer, Testy, administers with [members] joined (the viewer
  /// included), [invited] invitees and [knocking] knockers.
  Room courseRoom({required int members, int invited = 0, int knocking = 0}) {
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
      content: {'uuid': 'plan', 'l2': 'es'},
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
                child: CourseParticipantsPage(room: room),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester, find.byType(CourseParticipantsPage));
  }

  testWidgets('admins first, members by name, pending last, then invite', (
    tester,
  ) async {
    await pumpPage(
      tester,
      courseRoom(members: 4, invited: 1, knocking: 1),
      width: 400,
    );

    final cards = tester
        .widgetList<ParticipantCard>(find.byType(ParticipantCard))
        .toList();
    expect(cards.map((c) => c.user.displayName), [
      'Testy',
      'Member 1',
      'Member 2',
      'Member 3',
      'Invitee 1',
      'Knocker 1',
    ]);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Invited'), findsOneWidget);
    expect(find.text('Knocking'), findsOneWidget);
    expect(find.byType(ParticipantsInviteTile), findsOneWidget);
    expect(find.text('Invite'), findsOneWidget);
  });

  testWidgets('no card shows stats or a ring', (tester) async {
    await pumpPage(tester, courseRoom(members: 5), width: 400);

    final cards = tester.widgetList<ParticipantCard>(
      find.byType(ParticipantCard),
    );
    expect(cards, hasLength(5));
    expect(cards.every((c) => !c.showStats && c.gradient == null), isTrue);
    expect(find.byType(CourseMemberStats), findsNothing);
  });
}

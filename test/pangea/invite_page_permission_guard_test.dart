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
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';
import 'package:fluffychat/widgets/users/member_actions.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #8694 / CLIENT-DCA — the invite page is URL-addressable, so hiding the
/// entry buttons (#7875) never kept a member without invite power out of it,
/// and every invite they attempted failed with M_FORBIDDEN. The page stays
/// browsable as a roster; without `canInvite` the invite affordances disable
/// and a note says why. Approving a knock issues an invite, so the shared
/// member-actions "Approve" hides on the same condition.

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const roomId = '!session:fakeServer.notExisting';
  const guardNote = "You don't have permission to invite members here.";

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    // Avatar reads BotName.byEnvironment → Environment.botName, which needs
    // GetStorage (path_provider-backed) and dotenv to be readable.
    final tempDir = await Directory.systemTemp.createTemp('invite_guard');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': 'pangeabot',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  /// A joined room whose power levels use the course defaults (`invite: 50`),
  /// with the viewer at [ownPowerLevel]. It already has a join code: a
  /// privileged viewer without one triggers the page's code-generation
  /// request, whose timeout timer outlives the pumped tree.
  Room buildRoom({required int ownPowerLevel}) {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    room.setState(
      Event(
        type: EventTypes.RoomPowerLevels,
        content: {
          ...RoomDefaults.defaultPowerLevelsContent(),
          'users': {userId: ownPowerLevel},
        },
        stateKey: '',
        senderId: userId,
        eventId: '\$powerLevels',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    room.setState(
      Event(
        type: EventTypes.RoomJoinRules,
        content: {'join_rule': 'knock', 'access_code': 'abc12de'},
        stateKey: '',
        senderId: userId,
        eventId: '\$joinRules',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    client.rooms.add(room);
    return room;
  }

  /// English throughout — one locale per isolate, or a second set of delegates
  /// loads asynchronously and leaves the subtree empty for the pumped frames.
  ///
  /// Bounded pumps, not pumpAndSettle: the refer-a-friend image at the list's
  /// tail shows a progress placeholder that never resolves under test.
  Future<void> pumpInvitePage(WidgetTester tester) async {
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const PangeaInvitationSelection(
            roomId: roomId,
            embeddedCloseButton: SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('without invite power the page stays browsable with a note', (
    tester,
  ) async {
    buildRoom(ownPowerLevel: 0);
    await pumpInvitePage(tester);

    expect(find.text(guardNote), findsOneWidget);
    expect(find.byType(PangeaSearchBar), findsOneWidget);
  });

  testWidgets('with invite power there is no note', (tester) async {
    buildRoom(ownPowerLevel: 100);
    await pumpInvitePage(tester);

    expect(find.text(guardNote), findsNothing);
    expect(find.byType(PangeaSearchBar), findsOneWidget);
  });

  group('ApproveMemberAction', () {
    User knocker(Room room) => User(
      '@knocker:fakeServer.notExisting',
      membership: 'knock',
      room: room,
    );

    test('hidden without invite power — approval is an invite', () {
      final room = buildRoom(ownPowerLevel: 0);
      expect(ApproveMemberAction(user: knocker(room)).visible(), false);
    });

    test('visible for a knocking user when the viewer can invite', () {
      final room = buildRoom(ownPowerLevel: 100);
      expect(ApproveMemberAction(user: knocker(room)).visible(), true);
    });

    test('hidden for a joined user regardless of power', () {
      final room = buildRoom(ownPowerLevel: 100);
      final joined = User(
        '@member:fakeServer.notExisting',
        membership: 'join',
        room: room,
      );
      expect(ApproveMemberAction(user: joined).visible(), false);
    });
  });
}

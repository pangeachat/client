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
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #8694 / CLIENT-DCA — the invite page is URL-addressable, so hiding the
/// entry buttons (#7875) never kept a member without invite power out of it,
/// and every invite they attempted failed with M_FORBIDDEN. The page itself
/// now guards: without `canInvite` the search-and-invite UI is replaced by an
/// explanation, and with it the page is unchanged.

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
  /// with the viewer at [ownPowerLevel].
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
    client.rooms.add(room);
    return room;
  }

  /// English throughout — one locale per isolate, or a second set of delegates
  /// loads asynchronously and leaves the subtree empty for the pumped frames.
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
    await tester.pumpAndSettle();
  }

  // Only the guarded branch is pumped here: the privileged branch renders the
  // pre-change page verbatim, whose participant rows fetch public profiles the
  // fake controller deliberately doesn't stand up — and which side of the
  // ternary renders is decided by `room.canInvite` alone, whose truth table
  // (PL 0 / 50 / 100, membership) is pinned in
  // course_invite_permission_gate_test.dart.
  testWidgets('without invite power the invite UI is replaced', (tester) async {
    buildRoom(ownPowerLevel: 0);
    await pumpInvitePage(tester);

    expect(
      find.text("You don't have permission to invite members here."),
      findsOneWidget,
    );
    expect(find.byType(PangeaSearchBar), findsNothing);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details_content.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #8400 — the chat details page carried a chat description for every
/// non-space room, DMs included. In a 1:1 (with a person or with the bot) a
/// description names nothing anyone else will read, so the row was only ever
/// an empty-state distractor on an already busy page. Group chats keep it.
///
/// The gate is `!isDirectChat && !isBotDM`, and both halves earn their place:
/// a bot room carrying `bot_options.mode == direct_chat` is a DM the `m.direct`
/// account data alone does not report.

/// Skips `initMatrix()` — background push, notification listeners and the
/// Pangea controller are all irrelevant here and none of them stand up under
/// `flutter test`. `ChatDetailsButtonRow` only wants `Matrix.of(context).client`.
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
  const friendId = '@friend:fakeServer.notExisting';
  const botId = '@pangeabot:fakeServer.notExisting';
  const roomId = '!details:fakeServer.notExisting';

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    // Avatar reads BotName.byEnvironment → Environment.botName, which needs
    // GetStorage (path_provider-backed) and dotenv to be readable.
    final tempDir = await Directory.systemTemp.createTemp('chat_details_dm');
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
    // The participants tooltip reads the static controller while building.
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  /// The viewer is a room admin throughout: the edit control is gated on
  /// `isRoomAdmin`, so anything less would hide it for a reason other than the
  /// one under test.
  Room buildRoom({String? directChatWith, String? botMode}) {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    room.setState(
      Event(
        type: EventTypes.RoomPowerLevels,
        content: {
          ...RoomDefaults.defaultPowerLevelsContent(),
          'users': {userId: 100},
        },
        stateKey: '',
        senderId: userId,
        eventId: '\$powerLevels',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    if (botMode != null) {
      room.setState(
        Event(
          type: PangeaEventTypes.botOptions,
          content: {'mode': botMode},
          stateKey: '',
          senderId: userId,
          eventId: '\$botOptions',
          originServerTs: DateTime.now(),
          room: room,
        ),
      );
    }
    if (directChatWith != null) {
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          directChatWith: [roomId],
        },
      );
    }
    return room;
  }

  /// English throughout — one locale per isolate, or a second set of delegates
  /// loads asynchronously and leaves the subtree empty for the pumped frames.
  Future<void> pumpDetails(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          // The page brings its own Scaffold, AppBar, and scrolling.
          home: ChatDetailsContent(room: room),
        ),
      ),
    );
    // The L10n delegate resolves asynchronously — a single pumped frame leaves
    // the whole Localizations subtree empty, which would pass every negative
    // case here for the wrong reason.
    await tester.pumpAndSettle();
  }

  final descriptionText = find.byType(SelectableLinkify);
  final descriptionEditButton = find.widgetWithIcon(
    IconButton,
    Icons.edit_outlined,
  );

  testWidgets('a group chat still shows and can set its description', (
    tester,
  ) async {
    await pumpDetails(tester, buildRoom());

    expect(descriptionText, findsOneWidget);
    expect(descriptionEditButton, findsOneWidget);
  });

  testWidgets('a DM with another user has no description', (tester) async {
    await pumpDetails(tester, buildRoom(directChatWith: friendId));

    expect(descriptionText, findsNothing);
    expect(descriptionEditButton, findsNothing);
  });

  testWidgets('a DM with the bot has no description', (tester) async {
    await pumpDetails(tester, buildRoom(directChatWith: botId));

    expect(descriptionText, findsNothing);
    expect(descriptionEditButton, findsNothing);
  });

  testWidgets('a bot direct-chat room outside m.direct has no description', (
    tester,
  ) async {
    // The half of the gate `isDirectChat` cannot cover: the room is the bot DM
    // by its own bot options, but no `m.direct` entry points at it.
    final room = buildRoom(botMode: 'direct_chat');
    expect(room.isDirectChat, isFalse);

    await pumpDetails(tester, room);

    expect(descriptionText, findsNothing);
    expect(descriptionEditButton, findsNothing);
  });
}

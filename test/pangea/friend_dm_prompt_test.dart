import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/bot/bot_mode.dart';
import 'package:fluffychat/features/bot/bot_options_model.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/friend_dm_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat_list/dm_list_tile.dart';
import 'package:fluffychat/routes/chat_list/friend_dm_prompt.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #8395 — playtesters keep asking whether they can use the app to talk with
/// friends. Until the learner has a DM with another person, the chat list
/// carries an "Invite a friend" prompt whose button opens the New direct
/// message page. Every chat the app hands out unasked — the bot DM, the
/// support DM — is a direct chat too, so neither may dismiss the prompt; that
/// is exactly the learner it still has something to say to.

/// Skips `initMatrix()` — the CTA only wants a routed, localized subtree.
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
  // Environment.supportUserId for a non-staging SYNAPSE_URL.
  const supportId = '@support:pangea.chat';

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    // `BotName.byEnvironment` reads the GetStorage-backed environment override
    // before dotenv, and GetStorage needs a path_provider directory to open.
    final tempDir = await Directory.systemTemp.createTemp('friend_dm_prompt');
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
  });

  tearDown(() async {
    await client.dispose();
  });

  final Map<String, List<String>> directChats = {};
  setUp(directChats.clear);

  /// Adds a joined room to the client; [directChatWith] registers it in the
  /// `m.direct` account data, which is what makes a room a DM.
  Room addRoom(String id, {String? directChatWith, String? botMode}) {
    final room = Room(id: id, client: client, membership: Membership.join);
    if (botMode != null) {
      room.setState(
        Event(
          type: PangeaEventTypes.botOptions,
          content: BotOptionsModel(mode: botMode).toJson(),
          stateKey: '',
          senderId: userId,
          eventId: '\$botOptions$id',
          originServerTs: DateTime.now(),
          room: room,
        ),
      );
    }
    if (directChatWith != null) {
      directChats.putIfAbsent(directChatWith, () => []).add(id);
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: Map<String, dynamic>.from(directChats),
      );
    }
    client.rooms.add(room);
    return room;
  }

  group('hasFriendDM', () {
    test('is false for a brand new account', () {
      expect(client.hasFriendDM, isFalse);
    });

    test('a group chat is not a friend DM', () {
      final group = addRoom('!group:fakeServer.notExisting');
      expect(group.isDirectChat, isFalse);
      expect(client.hasFriendDM, isFalse);
    });

    test('a DM with Pangea Bot is not a friend DM', () {
      final botDM = addRoom(
        '!bot:fakeServer.notExisting',
        directChatWith: botId,
      );
      expect(botDM.isDirectChat, isTrue);
      expect(client.hasFriendDM, isFalse);
    });

    test('a bot chat identified by its bot options is not a friend DM', () {
      addRoom(
        '!botmode:fakeServer.notExisting',
        directChatWith: friendId,
        botMode: BotMode.directChat,
      );
      expect(client.hasFriendDM, isFalse);
    });

    test('a DM with the support account is not a friend DM', () {
      final supportDM = addRoom(
        '!support:fakeServer.notExisting',
        directChatWith: supportId,
      );
      expect(supportDM.isDirectChat, isTrue);
      expect(client.hasFriendDM, isFalse);
    });

    test('a note-to-self is not a friend DM', () {
      addRoom('!self:fakeServer.notExisting', directChatWith: userId);
      expect(client.hasFriendDM, isFalse);
    });

    test('a DM with another person is a friend DM', () {
      addRoom('!bot:fakeServer.notExisting', directChatWith: botId);
      addRoom('!support:fakeServer.notExisting', directChatWith: supportId);
      addRoom('!friend:fakeServer.notExisting', directChatWith: friendId);
      expect(client.hasFriendDM, isTrue);
    });
  });

  // The mobile chats sheet's content-fit height counts these tiles as rows, so
  // the prompt below them is not left behind a drag. The support tile also
  // reads the profile's instruction settings, which the fake controller leaves
  // "not ready" — the branch that suppresses the tile — so only the bot tile is
  // exercised positively here.
  group('DMListTile.tileCount', () {
    setUpAll(() => MatrixState.pangeaController = FakePangeaController());

    test('no bot DM: the bot tile renders and counts as a row', () {
      expect(DMListTile.showsBotTile(client), isTrue);
      expect(DMListTile.showsSupportTile(client), isFalse);
      expect(DMListTile.tileCount(client), 1);
    });

    test('a bot DM removes the bot tile', () {
      addRoom('!bot:fakeServer.notExisting', directChatWith: botId);
      expect(DMListTile.showsBotTile(client), isFalse);
      expect(DMListTile.tileCount(client), 0);
    });

    test('a support DM removes the support tile', () {
      addRoom('!support:fakeServer.notExisting', directChatWith: supportId);
      expect(DMListTile.showsSupportTile(client), isFalse);
    });
  });

  late GoRouter router;

  /// English throughout — one locale per isolate, or a second set of delegates
  /// loads asynchronously and leaves the subtree empty for the pumped frames.
  Future<void> pumpPrompt(WidgetTester tester) async {
    router = GoRouter(
      initialLocation: '/?left=chats',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: FriendDMPrompt()),
        ),
      ],
    );
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
        ),
      ),
    );
    // The L10n delegate resolves asynchronously — a single pumped frame leaves
    // the Localizations subtree empty, which would pass a negative case here
    // for the wrong reason.
    await tester.pumpAndSettle();
  }

  testWidgets('the button opens the New direct message panel', (tester) async {
    await pumpPrompt(tester);

    final context = tester.element(find.byType(FriendDMPrompt));
    await tester.tap(
      find.widgetWithText(FilledButton, L10n.of(context).inviteAFriend),
    );
    await tester.pump();

    final panels = parseOpenPanels(
      router.routerDelegate.currentConfiguration.uri,
    );
    expect(
      panels.left.any((t) => t.type == PanelTypesEnum.newprivatechat),
      isTrue,
      reason:
          'the CTA is the same new-chat action the panel header carries: '
          'got ${router.routerDelegate.currentConfiguration.uri}',
    );
    expect(
      panels.left.any((t) => t.type == PanelTypesEnum.chats),
      isTrue,
      reason: 'the DM picker opens beside the chat list, not instead of it',
    );
  });
}

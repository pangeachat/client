import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/friend_dm_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat_list/friend_dm_prompt_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'get_test_client.dart';

/// #8395 — playtesters keep asking whether they can use the app to talk with
/// friends. Until the learner has a DM with another person, the chat list
/// carries an "Invite a friend" prompt whose button opens the New direct
/// message page. A DM with Pangea Bot or with the support account is not a
/// friend, so neither one dismisses the prompt.

/// Skips `initMatrix()` — the prompt only wants `Matrix.of(context).client`.
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
    // BotName.byEnvironment → Environment.botName reads GetStorage
    // (path_provider-backed) and dotenv.
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

  /// Adds a joined room to the client; [directChatWith] registers it in the
  /// `m.direct` account data, which is what makes it a DM.
  Room addRoom(String id, {String? directChatWith, String? botMode}) {
    final room = Room(id: id, client: client, membership: Membership.join);
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
      directChats.putIfAbsent(directChatWith, () => []).add(id);
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: Map<String, dynamic>.from(directChats),
      );
    }
    client.rooms.add(room);
    return room;
  }

  setUp(directChats.clear);

  group('hasFriendDM', () {
    test('no rooms at all', () {
      expect(client.hasFriendDM, isFalse);
    });

    test('a group chat is not a friend DM', () {
      addRoom('!group:fakeServer.notExisting');
      expect(client.hasFriendDM, isFalse);
    });

    test('a DM with Pangea Bot is not a friend DM', () {
      addRoom('!bot:fakeServer.notExisting', directChatWith: botId);
      expect(client.hasFriendDM, isFalse);
    });

    test('a bot direct-chat room without m.direct is not a friend DM', () {
      addRoom('!botmode:fakeServer.notExisting', botMode: 'direct_chat');
      expect(client.hasFriendDM, isFalse);
    });

    test('a DM with the support account is not a friend DM', () {
      addRoom('!support:fakeServer.notExisting', directChatWith: supportId);
      expect(client.hasFriendDM, isFalse);
    });

    test('a DM with another person is a friend DM', () {
      addRoom('!bot:fakeServer.notExisting', directChatWith: botId);
      addRoom('!friend:fakeServer.notExisting', directChatWith: friendId);
      expect(client.hasFriendDM, isTrue);
    });
  });

  late GoRouter router;

  /// English throughout — one locale per isolate, or a second set of delegates
  /// loads asynchronously and leaves the subtree empty for the pumped frames.
  Future<void> pumpPrompt(WidgetTester tester, {bool visible = true}) async {
    router = GoRouter(
      initialLocation: '/?left=chats',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              Scaffold(body: FriendDMPrompt(visible: visible)),
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
    // the Localizations subtree empty, which would pass every negative case
    // here for the wrong reason.
    await tester.pumpAndSettle();
  }

  Finder inviteButton(WidgetTester tester) {
    final context = tester.element(find.byType(FriendDMPrompt));
    return find.widgetWithText(FilledButton, L10n.of(context).inviteAFriend);
  }

  testWidgets('shows the prompt when the learner has no DMs', (tester) async {
    await pumpPrompt(tester);
    expect(inviteButton(tester), findsOneWidget);
  });

  testWidgets('shows the prompt when the only DM is with Pangea Bot', (
    tester,
  ) async {
    addRoom('!bot:fakeServer.notExisting', directChatWith: botId);
    addRoom('!activity:fakeServer.notExisting');
    await pumpPrompt(tester);
    expect(inviteButton(tester), findsOneWidget);
  });

  testWidgets('hides the prompt once the learner has a DM with a friend', (
    tester,
  ) async {
    addRoom('!friend:fakeServer.notExisting', directChatWith: friendId);
    await pumpPrompt(tester);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('hides the prompt while the list is in search mode', (
    tester,
  ) async {
    await pumpPrompt(tester, visible: false);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('the button opens the New direct message panel', (tester) async {
    await pumpPrompt(tester);

    await tester.tap(inviteButton(tester));
    await tester.pumpAndSettle();

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

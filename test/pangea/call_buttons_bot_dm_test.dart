import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/chat_call_buttons.dart';
import 'package:fluffychat/routes/chat/calls/rtc_focus.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// The call buttons were gated on `isDirectChat` alone, and a bot DM IS a
/// direct chat -- so the Pangea Bot room offered Call and Video call. The bot
/// has no VoIP, so tapping one rang nobody and left the caller waiting out the
/// no-answer timeout.
///
/// Asserted over what RENDERS, not over the predicate alone. A test that only
/// calls the predicate leaves the site free to stop asking it: the gate could
/// be reverted to `isDirectChat` at the app bar with every test still green.
/// The gate therefore lives inside [ChatCallButtons], which mounts on its own,
/// and these pump it.
///
/// Both halves of `isBotDM` are exercised, because they catch different rooms:
/// `m.direct` names the bot as the other party, and `bot_options.mode` marks a
/// room the account data alone does not report as a bot DM.

/// Skips `initMatrix()` -- push, notification listeners and the Pangea
/// controller are all irrelevant here and none of them stand up under
/// `flutter test`. The buttons only want `Matrix.of(context).callService`,
/// which is served with a stubbed focus lookup so the network is never asked.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}

  @override
  CallService callServiceFor(String clientName) =>
      (widget as _TestMatrix).callService;
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
    required this.callService,
  });

  final CallService callService;

  @override
  MatrixState createState() => _TestMatrixState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const botId = '@pangeabot:fakeServer.notExisting';
  const friendId = '@friend:fakeServer.notExisting';
  const roomId = '!calls:fakeServer.notExisting';
  final homeserver = Uri.parse('https://fakeServer.notExisting');

  late Client client;
  late SharedPreferences store;
  CallService? callService;

  setUpAll(() async {
    // isBotDM reads BotName.byEnvironment, which needs GetStorage and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('call_buttons_bot');
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
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    client = await getTestClient();
    client.homeserver = homeserver;
  });

  tearDown(() async {
    await callService?.dispose();
    callService = null;
    await client.dispose();
  });

  Room buildRoom({String? directChatWith, String? botMode}) {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    if (botMode != null) {
      room.setState(
        Event(
          type: PangeaEventTypes.botOptions,
          content: {'mode': botMode},
          stateKey: '',
          senderId: botId,
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

  /// Serves `.well-known` and nothing else, so the focus half of the gate is a
  /// real answer rather than a stub of the widget's own decision.
  http.Client wellKnown({required bool advertisesFocus}) =>
      MockClient((request) async {
        if (request.url.path != '/.well-known/matrix/client') {
          return http.Response('{"errcode":"M_NOT_FOUND"}', 404);
        }
        return http.Response(
          jsonEncode({
            'm.homeserver': {'base_url': homeserver.toString()},
            if (advertisesFocus)
              'org.matrix.msc4143.rtc_foci': [
                {'type': 'livekit', 'livekit_service_url': 'http://sfu:7980'},
              ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

  /// Mounts the buttons where the chat header mounts them -- in an AppBar's
  /// actions -- so the widget is asked for exactly what the app asks it for.
  Future<void> pumpButtons(
    WidgetTester tester,
    Room room, {
    bool advertisesFocus = true,
  }) async {
    final service = callService = CallService(
      client,
      focusDiscovery: RtcFocusDiscovery(
        httpClient: wellKnown(advertisesFocus: advertisesFocus),
      ),
    );
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        callService: service,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(appBar: AppBar(actions: [ChatCallButtons(room)])),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final callButton = find.byIcon(Icons.call_outlined);
  final videoButton = find.byIcon(Icons.videocam_outlined);

  testWidgets('a DM with another person is offered calls', (tester) async {
    final room = buildRoom(directChatWith: friendId);
    expect(
      room.isDirectChat,
      isTrue,
      reason: 'the control must reach the gate',
    );

    await pumpButtons(tester, room);

    expect(callButton, findsOneWidget);
    expect(videoButton, findsOneWidget);
  });

  testWidgets('the bot DM named by m.direct is not', (tester) async {
    // The case the bug shipped: a real direct chat, so `isDirectChat` alone
    // said yes. Only the bot half can say no here.
    final room = buildRoom(directChatWith: botId);
    expect(room.isDirectChat, isTrue);

    await pumpButtons(tester, room);

    expect(callButton, findsNothing);
    expect(videoButton, findsNothing);
  });

  testWidgets('a bot room its options name, under some other user id, is not', (
    tester,
  ) async {
    // `m.direct` points at a user who is NOT the configured bot, so the name
    // check cannot fire -- `bot_options.mode` is the only thing that knows.
    final room = buildRoom(directChatWith: friendId, botMode: 'direct_chat');
    expect(room.isDirectChat, isTrue);

    await pumpButtons(tester, room);

    expect(callButton, findsNothing);
    expect(videoButton, findsNothing);
  });

  testWidgets('a group room is not offered calls at all', (tester) async {
    await pumpButtons(tester, buildRoom());

    expect(callButton, findsNothing);
    expect(videoButton, findsNothing);
  });

  testWidgets('a homeserver with no focus still offers nothing', (
    tester,
  ) async {
    // The room half of the gate is not the only one. Moving the buttons into
    // their own widget must not have left the focus lookup behind: without an
    // SFU there is nothing for the call to connect to.
    final room = buildRoom(directChatWith: friendId);

    await pumpButtons(tester, room, advertisesFocus: false);

    expect(callButton, findsNothing);
    expect(videoButton, findsNothing);
  });

  // The header's app bar cannot be mounted in a widget test -- `_appBarActions`
  // needs a live ChatController, which needs the whole chat route -- so this
  // reads the source instead. It is the cheapest honest pin on the one thing
  // the widget tests above cannot see: that the app bar still gets its call
  // buttons from ChatCallButtons, and holds no second, ungated copy of them.
  test('the chat header renders the buttons through ChatCallButtons', () {
    final source = File('lib/routes/chat/chat_view.dart').readAsStringSync();
    final start = source.indexOf('List<Widget> _appBarActions(');
    expect(start, greaterThan(-1), reason: '_appBarActions must still exist');
    final body = source.substring(start, source.indexOf('\n  }', start));

    expect(
      body.contains('ChatCallButtons('),
      isTrue,
      reason: 'the app bar must still mount the gated buttons',
    );
    for (final inlined in ['Icons.call_outlined', 'Icons.videocam_outlined']) {
      expect(
        body.contains(inlined),
        isFalse,
        reason: 'a call button written here again would bypass the gate',
      );
    }
  });
}

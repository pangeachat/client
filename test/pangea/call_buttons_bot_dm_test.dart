import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/chat_view.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'get_test_client.dart';

/// The call buttons were gated on `isDirectChat` alone, and a bot DM IS a
/// direct chat -- so the Pangea Bot room offered Call and Video call. The bot
/// has no VoIP, so tapping one rang nobody and left the caller waiting out the
/// no-answer timeout.
///
/// Both halves of `isBotDM` are exercised, because they catch different rooms:
/// `m.direct` names the bot as the other party, and `bot_options.mode` marks a
/// room the account data alone does not report as a bot DM.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const botId = '@pangeabot:fakeServer.notExisting';
  const friendId = '@friend:fakeServer.notExisting';
  const roomId = '!calls:fakeServer.notExisting';

  late Client client;

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
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
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

  test('a DM with another person is offered calls', () {
    final room = buildRoom(directChatWith: friendId);
    expect(
      room.isDirectChat,
      isTrue,
      reason: 'the control must reach the gate',
    );
    expect(roomOffersCalls(room), isTrue);
  });

  test('the bot DM named by m.direct is not', () {
    // The case the bug shipped: a real direct chat, so `isDirectChat` alone
    // said yes. Only the bot half can say no here.
    final room = buildRoom(directChatWith: botId);
    expect(room.isDirectChat, isTrue);
    expect(roomOffersCalls(room), isFalse);
  });

  test('a bot room its options name, under some other user id, is not', () {
    // `m.direct` points at a user who is NOT the configured bot, so the name
    // check cannot fire -- `bot_options.mode` is the only thing that knows.
    final room = buildRoom(directChatWith: friendId, botMode: 'direct_chat');
    expect(room.isDirectChat, isTrue);
    expect(roomOffersCalls(room), isFalse);
  });

  test('a group room is not offered calls at all', () {
    expect(roomOffersCalls(buildRoom()), isFalse);
  });
}

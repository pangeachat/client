import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/bot_seat_note.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'get_test_client.dart';

/// #9646 — where the bot took a waiting session's open seat on its own, the
/// chat says why. A marker a learner wrote by asking for the bot shows nothing
/// (activity-session.instructions.md, "The bot's seat").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const botId = '@bot:example.com';
  const learnerId = '@learner:example.com';
  const sessionId = '!session:example.com';

  late Client client;

  setUpAll(() async {
    // BotName.byEnvironment reads GetStorage and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('bot_seat_note');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {'BOT_NAME': botId, 'SYNAPSE_URL': 'https://example.com'},
    );
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() => client.dispose());

  Event marker({required String senderId, bool quiet = false}) => Event(
    type: PangeaEventTypes.botParticipant,
    content: {if (quiet) 'quiet': true},
    stateKey: '',
    senderId: senderId,
    eventId: '\$marker',
    originServerTs: DateTime.now(),
    room: Room(id: sessionId, client: client),
  );

  test('only the bot\'s own marker shows in the chat', () {
    expect(marker(senderId: botId).isBotSeatNote, isTrue);
    expect(marker(senderId: botId).isVisibleInGui, isTrue);
    expect(marker(senderId: botId).isCollapsedState, isFalse);
    expect(marker(senderId: learnerId).isBotSeatNote, isFalse);
    expect(marker(senderId: learnerId).isVisibleInGui, isFalse);
  });

  testWidgets('says the hour, or the day and that the learner starts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              BotSeatNote(marker(senderId: botId)),
              BotSeatNote(marker(senderId: botId, quiet: true)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = L10n.of(tester.element(find.byType(Column).first));
    expect(find.text(l10n.botTookSeatAfterAnHour), findsOneWidget);
    expect(find.text(l10n.botTookSeatAfterADay), findsOneWidget);
    expect(find.byIcon(Icons.close_outlined), findsNothing);
  });
}

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';

// Regression test for #8282: the known-good-voice gate must re-query the
// engine on every check, so a voice downloaded mid-session (after the dialog
// sent the user to system settings) is seen without an app restart.
// Design: client/.github/instructions/message-read-aloud.instructions.md
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');
  late List<Map<String, String>> deviceVoices;

  setUp(() {
    deviceVoices = [
      {'name': 'Anna', 'locale': 'de-DE', 'quality': 'default'},
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getVoices':
              return deviceVoices;
            default:
              return 1;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'gate sees an enhanced voice downloaded after the first check',
    () async {
      expect(await TtsController.hasKnownGoodVoiceFor('de-DE'), isFalse);

      // The user downloads an Enhanced voice in system settings and returns.
      deviceVoices.add({
        'name': 'Anna (Enhanced)',
        'locale': 'de-DE',
        'quality': 'enhanced',
      });

      expect(await TtsController.hasKnownGoodVoiceFor('de-DE'), isTrue);
    },
  );
}

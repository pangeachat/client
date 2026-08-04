import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';

/// #8117 — the enableTTS and autoReadAloudMessages toggles were replaced by
/// per-surface audio toggles (words, choices, incoming messages). Profiles
/// stored before the change must seed the new toggles from the old keys.
void main() {
  group('UserToolSettings audio toggle migration', () {
    test('defaults: words and choices on, incoming messages off', () {
      const settings = UserToolSettings();
      expect(settings.audioWords, isTrue);
      expect(settings.audioChoices, isTrue);
      expect(settings.audioIncomingMessages, isFalse);

      final fromEmpty = UserToolSettings.fromJson({});
      expect(fromEmpty.audioWords, isTrue);
      expect(fromEmpty.audioChoices, isTrue);
      expect(fromEmpty.audioIncomingMessages, isFalse);
    });

    test('legacy enableTTS off seeds words and choices off', () {
      final settings = UserToolSettings.fromJson({
        'ToolSetting.enableTTS': false,
      });
      expect(settings.audioWords, isFalse);
      expect(settings.audioChoices, isFalse);
      expect(settings.audioIncomingMessages, isFalse);
    });

    test('legacy autoReadAloudMessages on seeds incoming messages on', () {
      final settings = UserToolSettings.fromJson({
        'autoReadAloudMessages': true,
      });
      expect(settings.audioWords, isTrue);
      expect(settings.audioChoices, isTrue);
      expect(settings.audioIncomingMessages, isTrue);
    });

    test('new keys win over legacy keys', () {
      final settings = UserToolSettings.fromJson({
        'ToolSetting.enableTTS': false,
        'autoReadAloudMessages': true,
        'audioWords': true,
        'audioChoices': false,
        'audioIncomingMessages': false,
      });
      expect(settings.audioWords, isTrue);
      expect(settings.audioChoices, isFalse);
      expect(settings.audioIncomingMessages, isFalse);
    });

    test('toJson writes only the new keys', () {
      const settings = UserToolSettings(
        audioWords: false,
        audioChoices: true,
        audioIncomingMessages: true,
      );
      final json = settings.toJson();
      expect(json['audioWords'], isFalse);
      expect(json['audioChoices'], isTrue);
      expect(json['audioIncomingMessages'], isTrue);
      expect(json.containsKey('ToolSetting.enableTTS'), isFalse);
      expect(json.containsKey('autoReadAloudMessages'), isFalse);
    });

    test('round-trips through json', () {
      const settings = UserToolSettings(
        audioWords: false,
        audioChoices: false,
        audioIncomingMessages: true,
      );
      final restored = UserToolSettings.fromJson(settings.toJson());
      expect(restored, equals(settings));
    });

    test('copyWith updates each audio toggle independently', () {
      const settings = UserToolSettings();
      expect(settings.copyWith(audioWords: false).audioWords, isFalse);
      expect(settings.copyWith(audioWords: false).audioChoices, isTrue);
      expect(settings.copyWith(audioChoices: false).audioChoices, isFalse);
      expect(
        settings.copyWith(audioIncomingMessages: true).audioIncomingMessages,
        isTrue,
      );
    });
  });

  group('TtsUseCase', () {
    test('maps each use case to its audio tool setting', () {
      expect(TtsUseCase.words.toolSetting, ToolSetting.audioWords);
      expect(TtsUseCase.choices.toolSetting, ToolSetting.audioChoices);
      expect(
        TtsUseCase.incomingMessage.toolSetting,
        ToolSetting.audioIncomingMessages,
      );
    });

    test('audioSettings lists exactly the three audio toggles', () {
      expect(ToolSetting.audioSettings, [
        ToolSetting.audioWords,
        ToolSetting.audioChoices,
        ToolSetting.audioIncomingMessages,
      ]);
    });
  });
}

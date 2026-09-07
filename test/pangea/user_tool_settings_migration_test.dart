import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';

/// #8117 — the enableTTS and autoReadAloudMessages toggles were replaced by
/// per-surface audio toggles. Profiles stored before the change must seed the
/// words/choices toggles from the old enableTTS key.
///
/// #8264 — the incoming-messages toggle split into "On new message" and
/// "On message click", both default on. Deliberately NOT seeded from the
/// retired audioIncomingMessages key: it was opt-in default-off, so a stored
/// false is almost always the old default rather than a choice.
void main() {
  group('UserToolSettings audio toggle migration', () {
    test('defaults: all four audio toggles on', () {
      const settings = UserToolSettings();
      expect(settings.audioWords, isTrue);
      expect(settings.audioChoices, isTrue);
      expect(settings.audioOnNewMessage, isTrue);
      expect(settings.audioOnMessageClick, isTrue);

      final fromEmpty = UserToolSettings.fromJson({});
      expect(fromEmpty.audioWords, isTrue);
      expect(fromEmpty.audioChoices, isTrue);
      expect(fromEmpty.audioOnNewMessage, isTrue);
      expect(fromEmpty.audioOnMessageClick, isTrue);
    });

    test('legacy enableTTS off seeds words and choices off', () {
      final settings = UserToolSettings.fromJson({
        'ToolSetting.enableTTS': false,
      });
      expect(settings.audioWords, isFalse);
      expect(settings.audioChoices, isFalse);
      expect(settings.audioOnNewMessage, isTrue);
      expect(settings.audioOnMessageClick, isTrue);
    });

    // The retired keys were opt-in default-off, so a stored false is the old
    // default rather than a choice — everyone starts on after #8264.
    test('retired message-audio keys do not seed the new toggles', () {
      final settings = UserToolSettings.fromJson({
        'audioIncomingMessages': false,
        'autoReadAloudMessages': false,
      });
      expect(settings.audioOnNewMessage, isTrue);
      expect(settings.audioOnMessageClick, isTrue);
    });

    test('new keys win over legacy keys', () {
      final settings = UserToolSettings.fromJson({
        'ToolSetting.enableTTS': false,
        'audioIncomingMessages': true,
        'audioWords': true,
        'audioChoices': false,
        'audioOnNewMessage': false,
        'audioOnMessageClick': false,
      });
      expect(settings.audioWords, isTrue);
      expect(settings.audioChoices, isFalse);
      expect(settings.audioOnNewMessage, isFalse);
      expect(settings.audioOnMessageClick, isFalse);
    });

    test('toJson writes only the new keys', () {
      const settings = UserToolSettings(
        audioWords: false,
        audioChoices: true,
        audioOnNewMessage: false,
        audioOnMessageClick: true,
      );
      final json = settings.toJson();
      expect(json['audioWords'], isFalse);
      expect(json['audioChoices'], isTrue);
      expect(json['audioOnNewMessage'], isFalse);
      expect(json['audioOnMessageClick'], isTrue);
      expect(json.containsKey('ToolSetting.enableTTS'), isFalse);
      expect(json.containsKey('autoReadAloudMessages'), isFalse);
      expect(json.containsKey('audioIncomingMessages'), isFalse);
    });

    test('round-trips through json', () {
      const settings = UserToolSettings(
        audioWords: false,
        audioChoices: false,
        audioOnNewMessage: false,
        audioOnMessageClick: true,
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
        settings.copyWith(audioOnNewMessage: false).audioOnNewMessage,
        isFalse,
      );
      expect(
        settings.copyWith(audioOnNewMessage: false).audioOnMessageClick,
        isTrue,
      );
      expect(
        settings.copyWith(audioOnMessageClick: false).audioOnMessageClick,
        isFalse,
      );
    });
  });

  // #8466 — device autocorrect defaults on for Android only. The stored value
  // stays unresolved (null) until the user chooses, so each device applies
  // its own platform default; a stored false is always kept as a choice.
  group('UserToolSettings enableAutocorrect default', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('resolves to on for Android when never chosen', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(const UserToolSettings().enableAutocorrect, isTrue);
      expect(UserToolSettings.fromJson({}).enableAutocorrect, isTrue);
    });

    test('resolves to off for iOS when never chosen', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(const UserToolSettings().enableAutocorrect, isFalse);
      expect(UserToolSettings.fromJson({}).enableAutocorrect, isFalse);
    });

    test('a stored explicit off stays off on Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final settings = UserToolSettings.fromJson({'enableAutocorrect': false});
      expect(settings.enableAutocorrect, isFalse);
      expect(settings.enableAutocorrectChoice, isFalse);
    });

    test('a stored explicit on stays on regardless of platform', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        UserToolSettings.fromJson({
          'enableAutocorrect': true,
        }).enableAutocorrect,
        isTrue,
      );
    });

    test('toJson omits the key until the user chooses', () {
      expect(
        const UserToolSettings().toJson().containsKey('enableAutocorrect'),
        isFalse,
      );
      expect(
        const UserToolSettings(enableAutocorrect: false).toJson(),
        containsPair('enableAutocorrect', false),
      );
      expect(
        const UserToolSettings(enableAutocorrect: true).toJson(),
        containsPair('enableAutocorrect', true),
      );
    });

    test('never-chosen round-trips as never-chosen', () {
      final restored = UserToolSettings.fromJson(
        const UserToolSettings().toJson(),
      );
      expect(restored.enableAutocorrectChoice, isNull);
      expect(restored, equals(const UserToolSettings()));
    });

    test('copyWith of another toggle leaves the choice unresolved', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final updated = const UserToolSettings().copyWith(audioWords: false);
      expect(updated.enableAutocorrectChoice, isNull);
      expect(updated.toJson().containsKey('enableAutocorrect'), isFalse);
    });

    test('copyWith records an explicit choice', () {
      final updated = const UserToolSettings().copyWith(
        enableAutocorrect: false,
      );
      expect(updated.enableAutocorrectChoice, isFalse);
      expect(updated.enableAutocorrect, isFalse);
    });
  });

  group('TtsUseCase', () {
    test('maps each use case to its audio tool setting', () {
      expect(TtsUseCase.words.toolSetting, ToolSetting.audioWords);
      expect(TtsUseCase.choices.toolSetting, ToolSetting.audioChoices);
      expect(TtsUseCase.newMessage.toolSetting, ToolSetting.audioOnNewMessage);
      expect(
        TtsUseCase.messageClick.toolSetting,
        ToolSetting.audioOnMessageClick,
      );
    });

    test('audioSettings lists exactly the five audio toggles', () {
      expect(ToolSetting.audioSettings, [
        ToolSetting.audioWords,
        ToolSetting.audioChoices,
        // Ordered next to the choices audio it sequences (#8823).
        ToolSetting.listenFirst,
        ToolSetting.audioOnNewMessage,
        ToolSetting.audioOnMessageClick,
      ]);
    });

    test('only Listen First depends on choice audio', () {
      expect(ToolSetting.values.where((s) => s.requiresChoiceAudio), [
        ToolSetting.listenFirst,
      ]);
    });
  });
}

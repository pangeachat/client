import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/settings/settings_learning/read_aloud_voice_dialog.dart';

// Unit tests for the advice-variant picker shown when auto-read-aloud is
// toggled on without a known-good voice for the L2.
// Design: client/.github/instructions/message-read-aloud.instructions.md

void main() {
  group('ReadAloudVoiceAdvice.pick', () {
    test('desktop web browsers get the Chrome/Edge advice', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          ReadAloudVoiceAdvice.pick(isWeb: true, platform: platform),
          ReadAloudVoiceAdvice.desktopWeb,
        );
      }
    });

    test('mobile web gets the app advice, never another browser', () {
      // Every iOS browser is WebKit and shares Safari's voices, so pointing
      // mobile-web users at Chrome would not help them.
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        expect(
          ReadAloudVoiceAdvice.pick(isWeb: true, platform: platform),
          ReadAloudVoiceAdvice.mobileWeb,
        );
      }
    });

    test('native Android gets the voice-data install advice', () {
      expect(
        ReadAloudVoiceAdvice.pick(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        ReadAloudVoiceAdvice.android,
      );
    });

    test('native iOS gets the Spoken Content settings advice', () {
      expect(
        ReadAloudVoiceAdvice.pick(isWeb: false, platform: TargetPlatform.iOS),
        ReadAloudVoiceAdvice.ios,
      );
    });

    test('other Apple native builds fall back to the settings advice', () {
      expect(
        ReadAloudVoiceAdvice.pick(isWeb: false, platform: TargetPlatform.macOS),
        ReadAloudVoiceAdvice.ios,
      );
    });
  });
}

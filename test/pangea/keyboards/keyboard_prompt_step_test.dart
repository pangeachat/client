import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/keyboards/keyboard_language_repo.dart';
import 'package:fluffychat/features/keyboards/keyboard_prompt_step.dart';

void main() {
  group('resolveKeyboardPromptStep', () {
    test('no keyboard at all shows addKeyboard on Android', () {
      expect(
        resolveKeyboardPromptStep(
          platform: TargetPlatform.android,
          detection: KeyboardDetection.missing,
          hasObservedKeyboard: false,
        ),
        KeyboardPromptStep.addKeyboard,
      );
    });

    test('no keyboard at all shows addKeyboard on iOS', () {
      expect(
        resolveKeyboardPromptStep(
          platform: TargetPlatform.iOS,
          detection: KeyboardDetection.missing,
          hasObservedKeyboard: false,
        ),
        KeyboardPromptStep.addKeyboard,
      );
    });

    test('Android with a matching keyboard needs nothing further', () {
      expect(
        resolveKeyboardPromptStep(
          platform: TargetPlatform.android,
          detection: KeyboardDetection.matching,
          hasObservedKeyboard: false,
        ),
        isNull,
      );
    });

    test('iOS with the keyboard but not yet observed shows switchKeyboard', () {
      expect(
        resolveKeyboardPromptStep(
          platform: TargetPlatform.iOS,
          detection: KeyboardDetection.matching,
          hasObservedKeyboard: false,
        ),
        KeyboardPromptStep.switchKeyboard,
      );
    });

    test('iOS with the keyboard observed running needs nothing further', () {
      expect(
        resolveKeyboardPromptStep(
          platform: TargetPlatform.iOS,
          detection: KeyboardDetection.matching,
          hasObservedKeyboard: true,
        ),
        isNull,
      );
    });

    test('other platforms with a matching keyboard need nothing further', () {
      expect(
        resolveKeyboardPromptStep(
          platform: TargetPlatform.macOS,
          detection: KeyboardDetection.matching,
          hasObservedKeyboard: false,
        ),
        isNull,
      );
    });

    // Detection is advisory — an unreadable device must produce silence, not
    // a guess. iOS is the trap: treating unknown as "equipped" resolves to
    // the switch-keyboard step, which is a prompt.
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.macOS,
    ]) {
      test('unknown detection stays silent on $platform', () {
        expect(
          resolveKeyboardPromptStep(
            platform: platform,
            detection: KeyboardDetection.unknown,
            hasObservedKeyboard: false,
          ),
          isNull,
        );
      });
    }
  });
}

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/keyboards/keyboard_prompt_step.dart';

void main() {
  group('resolveKeyboardPromptStep', () {
    test('no keyboard at all shows addKeyboard on Android', () {
      expect(
        resolveKeyboardPromptStep(
          platform: TargetPlatform.android,
          hasMatchingKeyboard: false,
          hasObservedKeyboard: false,
        ),
        KeyboardPromptStep.addKeyboard,
      );
    });

    test('no keyboard at all shows addKeyboard on iOS', () {
      expect(
        resolveKeyboardPromptStep(
          platform: TargetPlatform.iOS,
          hasMatchingKeyboard: false,
          hasObservedKeyboard: false,
        ),
        KeyboardPromptStep.addKeyboard,
      );
    });

    test('Android with a matching keyboard needs nothing further', () {
      expect(
        resolveKeyboardPromptStep(
          platform: TargetPlatform.android,
          hasMatchingKeyboard: true,
          hasObservedKeyboard: false,
        ),
        isNull,
      );
    });

    test('iOS with the keyboard but not yet observed shows switchKeyboard', () {
      expect(
        resolveKeyboardPromptStep(
          platform: TargetPlatform.iOS,
          hasMatchingKeyboard: true,
          hasObservedKeyboard: false,
        ),
        KeyboardPromptStep.switchKeyboard,
      );
    });

    test('iOS with the keyboard observed running needs nothing further', () {
      expect(
        resolveKeyboardPromptStep(
          platform: TargetPlatform.iOS,
          hasMatchingKeyboard: true,
          hasObservedKeyboard: true,
        ),
        isNull,
      );
    });

    test('other platforms with a matching keyboard need nothing further', () {
      expect(
        resolveKeyboardPromptStep(
          platform: TargetPlatform.macOS,
          hasMatchingKeyboard: true,
          hasObservedKeyboard: false,
        ),
        isNull,
      );
    });
  });
}

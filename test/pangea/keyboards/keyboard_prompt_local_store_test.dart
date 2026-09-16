import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/keyboards/keyboard_prompt_local_store.dart';
import 'package:fluffychat/features/keyboards/keyboard_prompt_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ObservedKeyboardStore', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await ObservedKeyboardStore.initialize();
    });

    test('a never-observed language reads as not observed', () {
      expect(ObservedKeyboardStore.hasObservedKeyboard('es'), isFalse);
    });

    test('a null language reads as not observed', () {
      expect(ObservedKeyboardStore.hasObservedKeyboard(null), isFalse);
    });

    test('marking observed makes it read as observed immediately', () async {
      await ObservedKeyboardStore.markObserved('es-MX');
      expect(ObservedKeyboardStore.hasObservedKeyboard('es'), isTrue);
      expect(ObservedKeyboardStore.hasObservedKeyboard('es-ES'), isTrue);
    });

    test('observed state persists across a fresh initialize', () async {
      await ObservedKeyboardStore.markObserved('fr');
      await ObservedKeyboardStore.initialize();
      expect(ObservedKeyboardStore.hasObservedKeyboard('fr-CA'), isTrue);
    });

    test('observing one language leaves another unobserved', () async {
      await ObservedKeyboardStore.markObserved('es');
      expect(ObservedKeyboardStore.hasObservedKeyboard('ja'), isFalse);
    });
  });

  group('KeyboardPromptDismissalStore', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await KeyboardPromptDismissalStore.initialize();
    });

    test('a never-dismissed step reads as not dismissed', () {
      expect(
        KeyboardPromptDismissalStore.isDismissed(
          KeyboardPromptStep.addKeyboard,
          'es',
        ),
        isFalse,
      );
    });

    test('dismissing one step leaves the other step undismissed', () async {
      await KeyboardPromptDismissalStore.dismiss(
        KeyboardPromptStep.addKeyboard,
        'es',
      );
      expect(
        KeyboardPromptDismissalStore.isDismissed(
          KeyboardPromptStep.switchKeyboard,
          'es',
        ),
        isFalse,
      );
    });

    test(
      'dismissing for one target language leaves another language asking',
      () async {
        await KeyboardPromptDismissalStore.dismiss(
          KeyboardPromptStep.addKeyboard,
          'es',
        );
        expect(
          KeyboardPromptDismissalStore.isDismissed(
            KeyboardPromptStep.addKeyboard,
            'ja',
          ),
          isFalse,
        );
      },
    );

    test('dismissal persists across a fresh initialize', () async {
      await KeyboardPromptDismissalStore.dismiss(
        KeyboardPromptStep.switchKeyboard,
        'es',
      );
      await KeyboardPromptDismissalStore.initialize();
      expect(
        KeyboardPromptDismissalStore.isDismissed(
          KeyboardPromptStep.switchKeyboard,
          'es-MX',
        ),
        isTrue,
      );
    });
  });

  // A synchronous read that beats hydration returns the cold-start value, so
  // callers that can await must await `ready` first — otherwise a dismissed
  // prompt reappears and an observed keyboard reads as unobserved.
  group('hydration', () {
    test('ObservedKeyboardStore.ready loads persisted state', () async {
      SharedPreferences.setMockInitialValues({
        'keyboard_prompt_observed_languages': ['es'],
      });
      ObservedKeyboardStore.resetForTesting();

      expect(ObservedKeyboardStore.hasObservedKeyboard('es'), isFalse);
      await ObservedKeyboardStore.ready;
      expect(ObservedKeyboardStore.hasObservedKeyboard('es'), isTrue);
    });

    test('KeyboardPromptDismissalStore.ready loads persisted state', () async {
      SharedPreferences.setMockInitialValues({
        'keyboard_prompt_dismissed_steps': ['addKeyboard:es'],
      });
      KeyboardPromptDismissalStore.resetForTesting();

      expect(
        KeyboardPromptDismissalStore.isDismissed(
          KeyboardPromptStep.addKeyboard,
          'es',
        ),
        isFalse,
      );
      await KeyboardPromptDismissalStore.ready;
      expect(
        KeyboardPromptDismissalStore.isDismissed(
          KeyboardPromptStep.addKeyboard,
          'es',
        ),
        isTrue,
      );
    });

    test('ready is reused rather than reloading on every call', () async {
      SharedPreferences.setMockInitialValues({});
      ObservedKeyboardStore.resetForTesting();

      final first = ObservedKeyboardStore.ready;
      expect(identical(first, ObservedKeyboardStore.ready), isTrue);
      await first;
    });
  });
}

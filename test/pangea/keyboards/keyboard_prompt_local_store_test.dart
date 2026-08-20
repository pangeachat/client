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
}

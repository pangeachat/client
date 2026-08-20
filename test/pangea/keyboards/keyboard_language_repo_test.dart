import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/keyboards/keyboard_language_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hasKeyboardForLanguage (pure matching)', () {
    test('matches on the exact tag', () {
      expect(hasKeyboardForLanguage('es', ['en-US', 'es-ES']), isTrue);
    });

    test('ignores region — es-MX target matches an es-419 keyboard', () {
      expect(hasKeyboardForLanguage('es-MX', ['es-419']), isTrue);
    });

    test('is case-insensitive', () {
      expect(hasKeyboardForLanguage('ES', ['es-es']), isTrue);
    });

    test('reports no match when no keyboard shares the language', () {
      expect(hasKeyboardForLanguage('fr', ['en-US', 'es-ES']), isFalse);
    });

    test('never matches a non-language entry like iOS\'s "emoji"', () {
      expect(hasKeyboardForLanguage('fr', ['emoji']), isFalse);
    });

    test('reports no match against an empty keyboard list', () {
      expect(hasKeyboardForLanguage('fr', []), isFalse);
    });

    test('falls back to true for a malformed target code', () {
      expect(hasKeyboardForLanguage('', ['en-US']), isTrue);
    });
  });

  group('KeyboardLanguageRepo.hasMatchingKeyboard (platform detection)', () {
    const channel = MethodChannel('pangea/keyboard_languages');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('true when the platform reports a matching keyboard', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => ['es-MX']);

      expect(await KeyboardLanguageRepo.hasMatchingKeyboard('es'), isTrue);
    });

    test('false when enabled keyboards don\'t match', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => ['en-US', 'emoji'],
          );

      expect(await KeyboardLanguageRepo.hasMatchingKeyboard('es'), isFalse);
    });

    test('advisory: true when the platform reports nothing usable', () async {
      // No mock handler installed — the plugin call throws
      // MissingPluginException and the package-level wrapper returns [].
      expect(await KeyboardLanguageRepo.hasMatchingKeyboard('es'), isTrue);
    });
  });
}

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/keyboards/keyboard_language_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('detectKeyboard (pure classification)', () {
    test('matches on the exact tag', () {
      expect(
        detectKeyboard('es', ['en-US', 'es-ES']),
        KeyboardDetection.matching,
      );
    });

    test('ignores region — es-MX target matches an es-419 keyboard', () {
      expect(detectKeyboard('es-MX', ['es-419']), KeyboardDetection.matching);
    });

    test('is case-insensitive', () {
      expect(detectKeyboard('ES', ['es-es']), KeyboardDetection.matching);
    });

    test('missing when no keyboard shares the language', () {
      expect(
        detectKeyboard('fr', ['en-US', 'es-ES']),
        KeyboardDetection.missing,
      );
    });

    test('never matches a non-language entry like iOS\'s "emoji"', () {
      expect(detectKeyboard('fr', ['emoji']), KeyboardDetection.missing);
    });

    // Both of these are "we cannot tell", NOT "no keyboard" — resolving them
    // as missing would prompt on every misread device.
    test('unknown against an empty keyboard list', () {
      expect(detectKeyboard('fr', []), KeyboardDetection.unknown);
    });

    test('unknown for a malformed target code', () {
      expect(detectKeyboard('', ['en-US']), KeyboardDetection.unknown);
    });
  });

  group('KeyboardLanguageRepo.detect (platform detection)', () {
    const channel = MethodChannel('pangea/keyboard_languages');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('matching when the platform reports a matching keyboard', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => ['es-MX']);

      expect(
        await KeyboardLanguageRepo.detect('es'),
        KeyboardDetection.matching,
      );
    });

    test('missing when enabled keyboards don\'t match', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => ['en-US', 'emoji'],
          );

      expect(
        await KeyboardLanguageRepo.detect('es'),
        KeyboardDetection.missing,
      );
    });

    test('unknown when the platform reports nothing usable', () async {
      // No mock handler installed — the plugin call throws
      // MissingPluginException and the package-level wrapper returns [].
      expect(
        await KeyboardLanguageRepo.detect('es'),
        KeyboardDetection.unknown,
      );
    });
  });
}

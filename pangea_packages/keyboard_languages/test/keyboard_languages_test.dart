import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_languages/keyboard_languages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pangea/keyboard_languages');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns the tags the platform reports', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getEnabledLanguageTags');
          return ['en-US', 'es-MX', 'emoji'];
        });

    expect(await KeyboardLanguages.getEnabledLanguageTags(), [
      'en-US',
      'es-MX',
      'emoji',
    ]);
  });

  test('returns empty when the platform returns null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    expect(await KeyboardLanguages.getEnabledLanguageTags(), isEmpty);
  });

  test('returns empty when the channel is not implemented', () async {
    // No mock handler installed — invoking throws MissingPluginException.
    expect(await KeyboardLanguages.getEnabledLanguageTags(), isEmpty);
  });

  test('returns empty on a platform exception', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'error');
        });

    expect(await KeyboardLanguages.getEnabledLanguageTags(), isEmpty);
  });

  group('getCurrentInputModeLanguage', () {
    test('returns the language the platform reports', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getCurrentInputModeLanguage');
            return 'es-MX';
          });

      expect(await KeyboardLanguages.getCurrentInputModeLanguage(), 'es-MX');
    });

    test('returns null when nothing is focused', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);

      expect(await KeyboardLanguages.getCurrentInputModeLanguage(), isNull);
    });

    test('returns null when the channel is not implemented', () async {
      // No mock handler installed — invoking throws MissingPluginException.
      expect(await KeyboardLanguages.getCurrentInputModeLanguage(), isNull);
    });

    test('returns null on a platform exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'error');
          });

      expect(await KeyboardLanguages.getCurrentInputModeLanguage(), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/user/user_model.dart';

void main() {
  group('UserSettings.appLanguageIsTarget', () {
    test('defaults to false', () {
      expect(UserSettings().appLanguageIsTarget, isFalse);
    });

    test('round-trips through toJson/fromJson', () {
      final settings = UserSettings(
        sourceLanguage: 'en',
        targetLanguage: 'es',
        appLanguageIsTarget: true,
      );
      final restored = UserSettings.fromJson(settings.toJson());
      expect(restored.appLanguageIsTarget, isTrue);
    });

    test('absent key defaults to false when hydrating legacy data', () {
      final restored = UserSettings.fromJson({'source_language': 'en'});
      expect(restored.appLanguageIsTarget, isFalse);
    });

    test('copyWith updates the flag', () {
      expect(
        UserSettings().copyWith(appLanguageIsTarget: true).appLanguageIsTarget,
        isTrue,
      );
    });
  });
}

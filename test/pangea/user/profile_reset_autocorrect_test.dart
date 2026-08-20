import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/user/user_model.dart';

void main() {
  Profile makeProfile({String? targetLanguage, bool? autocorrectChoice}) =>
      Profile(
        userSettings: UserSettings(targetLanguage: targetLanguage),
        toolSettings: UserToolSettings(enableAutocorrect: autocorrectChoice),
      );

  group('Profile.resetAutocorrectIfLanguageChanged', () {
    test('clears an explicit choice when the target language changes', () {
      final previous = makeProfile(
        targetLanguage: 'fr',
        autocorrectChoice: false,
      );
      final updated = makeProfile(
        targetLanguage: 'es',
        autocorrectChoice: false,
      );

      final result = Profile.resetAutocorrectIfLanguageChanged(
        previous,
        updated,
      );

      expect(result.toolSettings.enableAutocorrectChoice, isNull);
    });

    test('leaves the choice alone when the target language is unchanged', () {
      final previous = makeProfile(
        targetLanguage: 'es',
        autocorrectChoice: false,
      );
      final updated = makeProfile(
        targetLanguage: 'es',
        autocorrectChoice: false,
      );

      final result = Profile.resetAutocorrectIfLanguageChanged(
        previous,
        updated,
      );

      expect(result.toolSettings.enableAutocorrectChoice, isFalse);
    });

    test('leaves an already-unset choice alone when unchanged', () {
      final previous = makeProfile(targetLanguage: 'es');
      final updated = makeProfile(targetLanguage: 'es');

      final result = Profile.resetAutocorrectIfLanguageChanged(
        previous,
        updated,
      );

      expect(result.toolSettings.enableAutocorrectChoice, isNull);
    });

    test('a first-time target language (null to a value) also resets', () {
      final previous = makeProfile(autocorrectChoice: true);
      final updated = makeProfile(
        targetLanguage: 'es',
        autocorrectChoice: true,
      );

      final result = Profile.resetAutocorrectIfLanguageChanged(
        previous,
        updated,
      );

      expect(result.toolSettings.enableAutocorrectChoice, isNull);
    });

    test('other fields on updated are left untouched', () {
      final previous = makeProfile(targetLanguage: 'fr');
      final updated = makeProfile(
        targetLanguage: 'es',
      ).copyWith(toolSettings: const UserToolSettings(audioWords: false));

      final result = Profile.resetAutocorrectIfLanguageChanged(
        previous,
        updated,
      );

      expect(result.toolSettings.audioWords, isFalse);
      expect(result.userSettings.targetLanguage, 'es');
    });
  });
}

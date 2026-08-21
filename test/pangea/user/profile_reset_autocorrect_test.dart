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

  // The settings page previews a language change before Save. The round trip
  // is what needs care: select another language, come back, and the choice
  // cleared on the way out has to return or it is what gets persisted.
  group('Profile.pendingAutocorrectChoice', () {
    bool? choice({
      String? savedLanguage = 'fr',
      bool? savedChoice = false,
      bool? pendingChoice,
      String? selectedLanguage,
      bool clearedByLanguageChange = false,
    }) => Profile.pendingAutocorrectChoice(
      savedLanguage: savedLanguage,
      savedChoice: savedChoice,
      pendingChoice: pendingChoice,
      selectedLanguage: selectedLanguage,
      clearedByLanguageChange: clearedByLanguageChange,
    );

    test('selecting a different language clears the choice', () {
      expect(choice(selectedLanguage: 'es', pendingChoice: false), isNull);
    });

    test('returning to the saved language restores the cleared choice', () {
      expect(
        choice(
          selectedLanguage: 'fr',
          pendingChoice: null,
          clearedByLanguageChange: true,
        ),
        isFalse,
      );
    });

    test('a restored null saved choice stays null', () {
      expect(
        choice(
          savedChoice: null,
          selectedLanguage: 'fr',
          pendingChoice: null,
          clearedByLanguageChange: true,
        ),
        isNull,
      );
    });

    test('a deliberate toggle survives re-selecting the saved language', () {
      expect(
        choice(
          selectedLanguage: 'fr',
          pendingChoice: true,
          clearedByLanguageChange: false,
        ),
        isTrue,
      );
    });

    test('a first-ever target language selection clears', () {
      expect(choice(savedLanguage: null, selectedLanguage: 'es'), isNull);
    });
  });
}

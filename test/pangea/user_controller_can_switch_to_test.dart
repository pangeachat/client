import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';

/// #8495 — the composed rule behind a content language chip's tint/tap
/// (profile.instructions.md, "Switching from context", point 6): a chip
/// offers a switch unless its language is already the target, or is the
/// learner's base language.
void main() {
  LanguageModel lang(String code) =>
      LanguageModel(langCode: code, displayName: code);

  test('a language matching the current target is not offered', () {
    expect(UserController.isCurrentTargetLanguage(lang('es'), 'es'), isTrue);
  });

  test('a regional variant of the target still counts as current', () {
    expect(UserController.isCurrentTargetLanguage(lang('es-MX'), 'es'), isTrue);
  });

  test('a different language is not the current target', () {
    expect(UserController.isCurrentTargetLanguage(lang('fr'), 'es'), isFalse);
  });

  test('a null target is never matched', () {
    expect(UserController.isCurrentTargetLanguage(lang('es'), null), isFalse);
  });

  group('canSwitchTo', () {
    test('a different, non-base language can be switched to', () {
      expect(
        UserController.canSwitchTo(
          lang('es'),
          targetLangCode: 'fr',
          baseLangCode: 'en',
        ),
        isTrue,
      );
    });

    test('the current target language is not offered', () {
      expect(
        UserController.canSwitchTo(
          lang('fr'),
          targetLangCode: 'fr',
          baseLangCode: 'en',
        ),
        isFalse,
      );
    });

    test('the base language is not offered', () {
      expect(
        UserController.canSwitchTo(
          lang('en'),
          targetLangCode: 'fr',
          baseLangCode: 'en',
        ),
        isFalse,
      );
    });
  });
}

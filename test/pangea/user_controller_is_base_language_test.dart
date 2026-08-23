import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';

/// #8495 — [UserController.isBaseLanguage] is the guard behind
/// profile.instructions.md, "Switching to the learner's base language is
/// refused, not attempted": [UserController.updateTargetLanguage] throws on
/// it, and the language switcher sheet disables that row before it's ever
/// tapped, using this same predicate so the two can't disagree.
void main() {
  LanguageModel lang(String code) =>
      LanguageModel(langCode: code, displayName: code);

  test('a language matching the base short code is refused', () {
    expect(UserController.isBaseLanguage(lang('es'), 'es'), isTrue);
  });

  test('a regional variant of the base language is refused too', () {
    // The base is plain Spanish; the target is the Mexico variant — same
    // short code, so still the learner's own language.
    expect(UserController.isBaseLanguage(lang('es-MX'), 'es'), isTrue);
    expect(UserController.isBaseLanguage(lang('es'), 'es-MX'), isTrue);
  });

  test('a different language is not refused', () {
    expect(UserController.isBaseLanguage(lang('fr'), 'es'), isFalse);
  });

  test('a null base language never refuses anything', () {
    expect(UserController.isBaseLanguage(lang('es'), null), isFalse);
  });
}

import 'package:get_storage/get_storage.dart';

/// Whether the learner has already seen the confirmation that switching to
/// a given language starts it at level 1 (profile.instructions.md,
/// "Switching from context" — "The first switch into a language with no
/// analytics at all says so once"). Unlike [LanguageMismatchRepo]'s cooldown,
/// this is permanent per language: once shown, it never shows again for that
/// language, regardless of whether the learner ever actually switches to it.
class FirstSwitchConfirmationRepo {
  static final GetStorage _storage = GetStorage('first_switch_confirmation');

  static bool hasConfirmed(String langCode) => _storage.read(langCode) == true;

  static Future<void> setConfirmed(String langCode) =>
      _storage.write(langCode, true);
}

import 'package:keyboard_languages/keyboard_languages.dart';

/// Whether the learner has a device keyboard for a given target language.
/// See target-language-keyboard.instructions.md.
abstract final class KeyboardLanguageRepo {
  /// Detection is advisory: wherever the platform reports nothing usable —
  /// unimplemented, failed, or no language-shaped tags at all — this reads
  /// as "equipped" rather than triggering a prompt. A missed prompt costs
  /// one learner some autocorrect; a wrong prompt nags every learner on
  /// every device we misread.
  static Future<bool> hasMatchingKeyboard(String targetLanguageCode) async {
    final enabledTags = await KeyboardLanguages.getEnabledLanguageTags();
    if (enabledTags.isEmpty) return true;
    return hasKeyboardForLanguage(targetLanguageCode, enabledTags);
  }
}

/// Whether [enabledTags] — raw platform language tags — includes a keyboard
/// for [targetLanguageCode]. Compares only the primary language subtag:
/// region and script don't change what a keyboard corrects toward, so
/// `es-MX` matches `es-419`. A tag that isn't shaped like a language code —
/// iOS's `"emoji"` entry, or a malformed target — can never match, which is
/// the same conservative "equipped" outcome the caller falls back to when a
/// platform reports nothing at all.
bool hasKeyboardForLanguage(
  String targetLanguageCode,
  List<String> enabledTags,
) {
  final target = primaryLanguageSubtag(targetLanguageCode);
  if (target == null) return true;
  return enabledTags.any((tag) => primaryLanguageSubtag(tag) == target);
}

/// The lowercase ISO 639 primary subtag of a BCP-47 tag (`es-419` → `es`),
/// or null if the tag doesn't start with a 2-3 letter language code. Public
/// so [ObservedKeyboardStore] can key its per-language state the same way.
String? primaryLanguageSubtag(String tag) {
  final primary = tag.split('-').first.toLowerCase();
  return RegExp(r'^[a-z]{2,3}$').hasMatch(primary) ? primary : null;
}

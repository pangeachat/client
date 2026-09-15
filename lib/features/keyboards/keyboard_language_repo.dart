import 'package:keyboard_languages/keyboard_languages.dart';

/// What this device can tell us about the learner's keyboards for a given
/// target language. See target-language-keyboard.instructions.md.
enum KeyboardDetection {
  /// The platform reported nothing usable — unimplemented, failed, or no
  /// language-shaped tags at all — so we cannot tell either way. Distinct
  /// from [matching] because "we can't tell" must produce no prompt at all,
  /// while [matching] still leads iOS to the switch-keyboard step.
  unknown,

  /// A keyboard for the target language is enabled on this device.
  matching,

  /// The learner's enabled keyboards were readable, and none of them is for
  /// the target language.
  missing,
}

/// Whether the learner has a device keyboard for a given target language.
/// See target-language-keyboard.instructions.md.
abstract final class KeyboardLanguageRepo {
  /// Detection is advisory: where the platform reports nothing usable this
  /// resolves to [KeyboardDetection.unknown], which prompts nothing at all.
  /// A missed prompt costs one learner some autocorrect; a wrong prompt nags
  /// every learner on every device we misread.
  static Future<KeyboardDetection> detect(String targetLanguageCode) async =>
      detectKeyboard(
        targetLanguageCode,
        await KeyboardLanguages.getEnabledLanguageTags(),
      );
}

/// Classifies [enabledTags] — raw platform language tags — against
/// [targetLanguageCode]. Compares only the primary language subtag: region
/// and script don't change what a keyboard corrects toward, so `es-MX`
/// matches `es-419`. A tag that isn't shaped like a language code (iOS's
/// `"emoji"` entry) simply never matches; an empty tag list or a malformed
/// target means we cannot tell, which is [KeyboardDetection.unknown] rather
/// than a false [KeyboardDetection.missing] or [KeyboardDetection.matching].
KeyboardDetection detectKeyboard(
  String targetLanguageCode,
  List<String> enabledTags,
) {
  final target = primaryLanguageSubtag(targetLanguageCode);
  if (target == null || enabledTags.isEmpty) return KeyboardDetection.unknown;
  return enabledTags.any((tag) => primaryLanguageSubtag(tag) == target)
      ? KeyboardDetection.matching
      : KeyboardDetection.missing;
}

/// The lowercase ISO 639 primary subtag of a BCP-47 tag (`es-419` → `es`),
/// or null if the tag doesn't start with a 2-3 letter language code. Public
/// so [ObservedKeyboardStore] can key its per-language state the same way.
String? primaryLanguageSubtag(String tag) {
  final primary = tag.split('-').first.toLowerCase();
  return RegExp(r'^[a-z]{2,3}$').hasMatch(primary) ? primary : null;
}

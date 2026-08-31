import 'package:flutter/services.dart';

/// The language of every keyboard the user has enabled on the device, on iOS
/// and Android. See target-language-keyboard.instructions.md in the client
/// repo.
abstract final class KeyboardLanguages {
  static const MethodChannel _channel = MethodChannel(
    'pangea/keyboard_languages',
  );

  /// One tag per enabled keyboard, exactly as the platform reports it —
  /// including non-language entries such as iOS's `"emoji"` input mode; the
  /// caller decides which entries are language-shaped.
  ///
  /// Empty wherever the platform call isn't implemented or fails. A real
  /// device always has at least one keyboard enabled, so an empty result
  /// means "unknown", not "no keyboards" — callers should treat it that way
  /// rather than as evidence the learner needs a keyboard.
  static Future<List<String>> getEnabledLanguageTags() async {
    try {
      final tags = await _channel.invokeListMethod<String>(
        'getEnabledLanguageTags',
      );
      return tags ?? [];
    } on PlatformException {
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  /// The languages the device can spell check, exactly as the platform names
  /// them — iOS uses underscores (`en_US`), and lists some languages bare
  /// (`ar`, `hi`) and others only with a region (`es_ES`, `es_MX`).
  ///
  /// A language is checkable only if it appears here: iOS answers null for a
  /// tag it does not list, so asking for a bare `es` fails while its own
  /// `es_ES` succeeds. Callers must resolve the language they want against
  /// this list rather than constructing a tag themselves.
  ///
  /// Empty means "unknown" — unimplemented, no checker enabled, or a failed
  /// call — not "nothing is checkable".
  static Future<List<String>> getAvailableSpellCheckLanguages() async {
    try {
      final tags = await _channel.invokeListMethod<String>(
        'getAvailableSpellCheckLanguages',
      );
      return tags ?? [];
    } on PlatformException {
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  /// The primary language of whatever keyboard mode is active on the
  /// currently focused text input, or null when nothing is focused, the
  /// platform doesn't implement this, or the call fails.
  ///
  /// iOS only — Android has no equivalent because the composer already
  /// points the keyboard at the target language itself
  /// (target-language-keyboard.instructions.md); on Android and every other
  /// platform this simply resolves to null.
  static Future<String?> getCurrentInputModeLanguage() async {
    try {
      return await _channel.invokeMethod<String>('getCurrentInputModeLanguage');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

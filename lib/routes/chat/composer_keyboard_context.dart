import 'package:flutter/widgets.dart';

import 'package:text_input_context/text_input_context.dart';

/// Keeps the iOS keyboard language a learner picks for the chat composer
/// sticky across chats and app launches, per target language (#8465).
///
/// iOS restores the last-used keyboard language for a text field whose
/// `textInputContextIdentifier` it recognises; Flutter exposes no such hook,
/// so the `text_input_context` plugin patches the engine's text input view to
/// report the identifier set here. The identifier is set while the composer
/// has focus and cleared when it loses focus, so every other field (search,
/// display name, password) keeps the device default. It is keyed on the target
/// language so switching L2 does not inherit the previous language's keyboard.
///
/// Create this right after the composer's [FocusNode], before any TextField
/// using it is built: `EditableText` opens the platform connection from its
/// own listener on the same node, and FocusNode notifies listeners in
/// registration order, so ours must be first for the identifier to be in place
/// when iOS reads it. A no-op off iOS.
class ComposerKeyboardContext {
  static const identifierPrefix = 'pangea.composer.';

  final FocusNode focusNode;

  /// The learner's current target language code, read at focus time so a
  /// language change between focuses is picked up without re-wiring.
  final String? Function() targetLanguageCode;

  ComposerKeyboardContext({
    required this.focusNode,
    required this.targetLanguageCode,
  }) {
    focusNode.addListener(_onFocusChanged);
  }

  /// The identifier for [langCode], or null when no target language is set —
  /// no language, no keyboard to remember.
  static String? identifierFor(String? langCode) =>
      langCode == null || langCode.isEmpty
      ? null
      : '$identifierPrefix$langCode';

  void _onFocusChanged() {
    TextInputContext.setIdentifier(
      focusNode.hasFocus ? identifierFor(targetLanguageCode()) : null,
    );
  }

  void dispose() {
    focusNode.removeListener(_onFocusChanged);
  }
}

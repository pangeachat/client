import 'package:flutter/widgets.dart';

import 'package:text_input_context/text_input_context.dart';

/// Keeps the iOS keyboard language a learner picks for the chat composer
/// sticky across chats and app launches, per target language (#8465).
///
/// iOS restores the last-used keyboard language for a text field whose
/// `textInputContextIdentifier` it recognises; Flutter exposes no such hook,
/// so the `text_input_context` plugin patches the engine's text input view to
/// report the identifier set here. The identifier is set while the composer
/// has focus and cleared when it loses focus **or is unmounted**, so every
/// other field (search, display name, password) keeps the device default. It
/// is keyed on the target language so switching L2 does not inherit the
/// previous language's keyboard.
///
/// Wrap the composer's TextField (or the Autocomplete that builds it) in this
/// widget: its listener is registered in [State.initState], before the child
/// `EditableText` registers its own on the same [FocusNode], and FocusNode
/// notifies listeners in registration order — so the identifier is in place
/// when iOS reads it on attach. Clearing on [State.dispose] matters because a
/// FocusNode that is detached while focused (the composer being unmounted by
/// a navigation to chat search or settings) never notifies its listeners, and
/// without the clear the next field's text-input view would inherit the
/// composer's identifier and record its keyboard switches under it.
///
/// A no-op off iOS.
class ComposerKeyboardContext extends StatefulWidget {
  static const identifierPrefix = 'pangea.composer.';

  final FocusNode focusNode;

  /// The learner's current target language code, read at focus time so a
  /// language change between focuses is picked up without re-wiring.
  final String? Function() targetLanguageCode;

  final Widget child;

  const ComposerKeyboardContext({
    super.key,
    required this.focusNode,
    required this.targetLanguageCode,
    required this.child,
  });

  /// The identifier for [langCode], or null when no target language is set —
  /// no language, no keyboard to remember.
  static String? identifierFor(String? langCode) =>
      langCode == null || langCode.isEmpty
      ? null
      : '$identifierPrefix$langCode';

  @override
  State<ComposerKeyboardContext> createState() =>
      _ComposerKeyboardContextState();
}

class _ComposerKeyboardContextState extends State<ComposerKeyboardContext> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(ComposerKeyboardContext oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    TextInputContext.setIdentifier(null);
    super.dispose();
  }

  void _onFocusChanged() {
    TextInputContext.setIdentifier(
      widget.focusNode.hasFocus
          ? ComposerKeyboardContext.identifierFor(widget.targetLanguageCode())
          : null,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

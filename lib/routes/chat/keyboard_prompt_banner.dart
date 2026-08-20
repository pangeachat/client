import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:keyboard_languages/keyboard_languages.dart';

import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/features/keyboards/keyboard_language_repo.dart';
import 'package:fluffychat/features/keyboards/keyboard_prompt_local_store.dart';
import 'package:fluffychat/features/keyboards/keyboard_prompt_step.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/enable_autocorrect_dialog.dart';

/// The two-step keyboard-setup ladder shown above the composer — see
/// target-language-keyboard.instructions.md, "The prompt ladder". Renders
/// nothing until detection says a step applies, and nothing once the
/// learner dismisses it or resolves it themselves.
///
/// A sibling of the composer's Material box, not a child of it — matching
/// how DegradationBanner sits in ChatInputBar, so its shadow isn't clipped
/// by the box's Clip.hardEdge.
class KeyboardPromptBanner extends StatefulWidget {
  final FocusNode composerFocusNode;

  /// Read fresh on every check rather than passed once, so a language
  /// change picked up mid-session (or a room switch reusing this widget)
  /// is seen without needing a new widget instance.
  final String? Function() targetLanguageCode;

  const KeyboardPromptBanner({
    super.key,
    required this.composerFocusNode,
    required this.targetLanguageCode,
  });

  @override
  State<KeyboardPromptBanner> createState() => KeyboardPromptBannerState();
}

class KeyboardPromptBannerState extends State<KeyboardPromptBanner>
    with WidgetsBindingObserver {
  KeyboardPromptStep? _step;
  Timer? _pollTimer;
  String? _polledLanguageCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.composerFocusNode.addListener(_onFocusChange);
    if (widget.composerFocusNode.hasFocus) _refresh();
  }

  @override
  void didUpdateWidget(covariant KeyboardPromptBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composerFocusNode != widget.composerFocusNode) {
      oldWidget.composerFocusNode.removeListener(_onFocusChange);
      widget.composerFocusNode.addListener(_onFocusChange);
    }
    // Reusing this widget for a different room (same composer FocusNode)
    // means a different target language — re-resolve rather than keep
    // showing the previous room's step.
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.composerFocusNode.removeListener(_onFocusChange);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Adding a keyboard sends the learner to Settings and back — re-check
    // what they did the moment they return (target-language-keyboard
    // .instructions.md, "What each platform tells us").
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _onFocusChange() {
    if (widget.composerFocusNode.hasFocus) _refresh();
  }

  Future<void> _refresh() async {
    final languageCode = widget.targetLanguageCode();
    if (languageCode == null) {
      _stopPolling();
      if (mounted && _step != null) setState(() => _step = null);
      return;
    }

    final hasKeyboard = await KeyboardLanguageRepo.hasMatchingKeyboard(
      languageCode,
    );
    // The target language may have changed while that call was in flight.
    if (!mounted || widget.targetLanguageCode() != languageCode) return;

    final step = resolveKeyboardPromptStep(
      platform: defaultTargetPlatform,
      hasMatchingKeyboard: hasKeyboard,
      hasObservedKeyboard: ObservedKeyboardStore.hasObservedKeyboard(
        languageCode,
      ),
    );

    if (step == KeyboardPromptStep.switchKeyboard) {
      _startPolling(languageCode);
    } else {
      _stopPolling();
    }

    final shown =
        step != null &&
        !KeyboardPromptDismissalStore.isDismissed(step, languageCode);
    if (mounted) setState(() => _step = shown ? step : null);
  }

  /// While the "switch to it" step is showing, polls the live keyboard mode
  /// so the step clears itself the moment the learner taps the globe key —
  /// see target-language-keyboard.instructions.md, "The prompt ladder".
  void _startPolling(String languageCode) {
    if (_pollTimer != null && _polledLanguageCode == languageCode) return;
    _stopPolling();
    _polledLanguageCode = languageCode;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final current = await KeyboardLanguages.getCurrentInputModeLanguage();
      if (current == null) return;
      if (primaryLanguageSubtag(current) !=
          primaryLanguageSubtag(languageCode)) {
        return;
      }
      await ObservedKeyboardStore.markObserved(languageCode);
      _stopPolling();
      if (mounted) setState(() => _step = null);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _polledLanguageCode = null;
  }

  void _dismiss() {
    final languageCode = widget.targetLanguageCode();
    final step = _step;
    if (languageCode == null || step == null) return;
    KeyboardPromptDismissalStore.dismiss(step, languageCode);
    setState(() => _step = null);
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case null:
        return const SizedBox.shrink();
      case KeyboardPromptStep.addKeyboard:
        return InlineTooltip(
          message: L10n.of(context).keyboardPromptAddKeyboardMessage,
          isClosed: false,
          onClose: _dismiss,
          extraContent: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (context) => const EnableAutocorrectDialog(),
              ),
              child: Text(L10n.of(context).keyboardPromptAddKeyboardAction),
            ),
          ),
        );
      case KeyboardPromptStep.switchKeyboard:
        return InlineTooltip(
          message: L10n.of(context).keyboardPromptSwitchKeyboardMessage,
          isClosed: false,
          onClose: _dismiss,
        );
    }
  }
}

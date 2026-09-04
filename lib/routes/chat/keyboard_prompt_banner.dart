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

  /// Bumped whenever a resolve or a poll is superseded. Cancelling a
  /// [Timer] does not cancel a callback already suspended at an await, and
  /// neither does starting a newer [_refresh], so every async continuation
  /// re-checks its generation before touching state — otherwise a stale
  /// callback can clear the step belonging to a newer target language.
  int _refreshGeneration = 0;
  int _pollGeneration = 0;

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
    // Bumps both generations as well as cancelling the timer, so any
    // continuation still suspended at an await is a no-op.
    _refreshGeneration++;
    _stopPolling();
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
    if (widget.composerFocusNode.hasFocus) {
      _refresh();
      return;
    }
    // The prompt speaks to the keyboard the learner is about to type with,
    // so it has no business being on screen — or polling — once the composer
    // is not focused.
    _clear();
  }

  void _clear() {
    _refreshGeneration++;
    _stopPolling();
    if (mounted && _step != null) setState(() => _step = null);
  }

  Future<void> _refresh() async {
    // Covers the unfocused-resume path too: didChangeAppLifecycleState fires
    // for every resume, whether or not the composer holds focus.
    if (!widget.composerFocusNode.hasFocus) {
      _clear();
      return;
    }

    final languageCode = widget.targetLanguageCode();
    if (languageCode == null) {
      _clear();
      return;
    }

    final generation = ++_refreshGeneration;
    // Reading either store before it has loaded resurrects a dismissed
    // prompt and reads an observed keyboard as unobserved. Only a cold start
    // pays for the wait; once startup has hydrated them this is a plain
    // synchronous check.
    if (!ObservedKeyboardStore.isHydrated ||
        !KeyboardPromptDismissalStore.isHydrated) {
      await ObservedKeyboardStore.ready;
      await KeyboardPromptDismissalStore.ready;
    }
    final detection = await KeyboardLanguageRepo.detect(languageCode);
    if (!_stillCurrent(generation, languageCode)) return;

    final step = resolveKeyboardPromptStep(
      platform: defaultTargetPlatform,
      detection: detection,
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
    setState(() => _step = shown ? step : null);
  }

  /// Whether an async continuation may still act: not disposed, not
  /// superseded by a newer refresh, still the same target language, and the
  /// composer still focused.
  bool _stillCurrent(int generation, String languageCode) =>
      mounted &&
      generation == _refreshGeneration &&
      widget.targetLanguageCode() == languageCode &&
      widget.composerFocusNode.hasFocus;

  /// While the "switch to it" step is showing, polls the live keyboard mode
  /// so the step clears itself the moment the learner taps the globe key —
  /// see target-language-keyboard.instructions.md, "The prompt ladder".
  void _startPolling(String languageCode) {
    if (_pollTimer != null && _polledLanguageCode == languageCode) return;
    _stopPolling();
    final generation = _pollGeneration;
    _polledLanguageCode = languageCode;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final current = await KeyboardLanguages.getCurrentInputModeLanguage();
      // This tick may have been suspended at the await while the learner
      // changed target language. Cancelling the timer cannot undo that, and
      // the generation alone is not enough — the replacement poll may not
      // have started yet — so the language it was started for has to still
      // be the current one.
      if (!_pollStillCurrent(generation, languageCode)) return;
      if (current == null) return;
      if (primaryLanguageSubtag(current) !=
          primaryLanguageSubtag(languageCode)) {
        return;
      }
      await ObservedKeyboardStore.markObserved(languageCode);
      if (!_pollStillCurrent(generation, languageCode)) return;
      _stopPolling();
      setState(() => _step = null);
    });
  }

  /// The poll equivalent of [_stillCurrent] — see the ordering note in
  /// [_startPolling] for why the language check carries the weight here.
  bool _pollStillCurrent(int generation, String languageCode) =>
      mounted &&
      generation == _pollGeneration &&
      widget.targetLanguageCode() == languageCode &&
      widget.composerFocusNode.hasFocus;

  void _stopPolling() {
    _pollGeneration++;
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
                builder: (context) => EnableAutocorrectDialog(
                  title: L10n.of(context).addKeyboardDialogTitle,
                ),
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

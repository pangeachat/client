import 'package:flutter/foundation.dart';

/// Which rung of the keyboard-setup ladder to show above the composer. See
/// target-language-keyboard.instructions.md, "The prompt ladder": getting
/// equipped is two steps on iOS, one on Android, and each step is shown only
/// to a learner who hasn't already completed it.
enum KeyboardPromptStep {
  /// The learner has no keyboard matching the target language at all.
  /// Android and iOS both show this.
  addKeyboard,

  /// iOS only: the learner has the keyboard, but the composer hasn't yet
  /// seen them typing with it. Clears itself the moment they switch — no
  /// dismissal needed to make it go away.
  switchKeyboard,
}

/// Resolves the current ladder step from what's known about this device, or
/// null when nothing needs prompting. Pure and platform-blind so every
/// branch is unit-testable without a running app; callers gather the inputs
/// from [KeyboardLanguageRepo], [ObservedKeyboardStore], and the platform.
KeyboardPromptStep? resolveKeyboardPromptStep({
  required TargetPlatform platform,
  required bool hasMatchingKeyboard,
  required bool hasObservedKeyboard,
}) {
  if (!hasMatchingKeyboard) return KeyboardPromptStep.addKeyboard;
  // Android's composer already redirects the keyboard itself — there is
  // nothing left to walk the learner through.
  if (platform != TargetPlatform.iOS) return null;
  if (!hasObservedKeyboard) return KeyboardPromptStep.switchKeyboard;
  return null;
}

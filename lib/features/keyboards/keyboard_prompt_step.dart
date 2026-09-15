import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/keyboards/keyboard_language_repo.dart';

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
  required KeyboardDetection detection,
  required bool hasObservedKeyboard,
}) {
  switch (detection) {
    // Detection is advisory: when the platform tells us nothing usable we
    // stay silent rather than guess. Treating unknown as "equipped" would
    // send iOS on to the switch-keyboard step, which is a prompt, not
    // silence.
    case KeyboardDetection.unknown:
      return null;
    case KeyboardDetection.missing:
      return KeyboardPromptStep.addKeyboard;
    case KeyboardDetection.matching:
      // Android's composer already redirects the keyboard itself — there is
      // nothing left to walk the learner through.
      if (platform != TargetPlatform.iOS) return null;
      return hasObservedKeyboard ? null : KeyboardPromptStep.switchKeyboard;
  }
}

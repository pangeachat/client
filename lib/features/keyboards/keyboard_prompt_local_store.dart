import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/keyboards/keyboard_language_repo.dart';
import 'package:fluffychat/features/keyboards/keyboard_prompt_step.dart';

/// Per-device record of every target language this device has been observed
/// typing with a matching keyboard. Read synchronously — like
/// [UserToolSettings.enableAutocorrectPlatformDefault], the getter it backs
/// is called from build methods that can't await a platform channel — so the
/// cache is loaded once at startup and every subsequent read serves from
/// memory. See target-language-keyboard.instructions.md, "When autocorrect
/// turns on".
///
/// Local rather than synced: a device's keyboards are a fact about that
/// device, not about the learner's account, the same reasoning that keeps
/// [UserToolSettings.enableAutocorrectPlatformDefault] itself per-device.
abstract final class ObservedKeyboardStore {
  static const _prefsKey = 'keyboard_prompt_observed_languages';

  static Set<String> _observed = {};
  static Future<void>? _hydration;
  static bool _hydrated = false;

  static Future<void> initialize() => _hydration = _hydrate();

  /// Whether the on-disk state is already in memory, so a caller can skip
  /// awaiting [ready] on the hot path once startup has hydrated it.
  static bool get isHydrated => _hydrated;

  /// Completes once the on-disk state is in memory. Callers that can await —
  /// the composer banner, profile initialization — must do so before reading,
  /// or a dismissed prompt reappears and an observed keyboard reads as
  /// unobserved for as long as the read beats the load.
  static Future<void> get ready => _hydration ??= _hydrate();

  static Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    _observed = (prefs.getStringList(_prefsKey) ?? []).toSet();
    _hydrated = true;
  }

  /// Returns the store to its cold-start state so a test can exercise a read
  /// that races hydration.
  @visibleForTesting
  static void resetForTesting() {
    _hydration = null;
    _observed = {};
    _hydrated = false;
  }

  static bool hasObservedKeyboard(String? languageCode) {
    if (languageCode == null) return false;
    final subtag = primaryLanguageSubtag(languageCode);
    return subtag != null && _observed.contains(subtag);
  }

  static Future<void> markObserved(String? languageCode) async {
    if (languageCode == null) return;
    final subtag = primaryLanguageSubtag(languageCode);
    if (subtag == null || _observed.contains(subtag)) return;
    _observed = {..._observed, subtag};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _observed.toList());
  }
}

/// Per-device record of which keyboard-prompt ladder steps the learner has
/// dismissed, per target language — dismissing the prompt for Spanish says
/// nothing about Japanese (target-language-keyboard.instructions.md,
/// "Delivery"). Local for the same reason as [ObservedKeyboardStore]:
/// keyboard setup is a per-device fact, so a dismissal on one device
/// shouldn't hide the prompt on another where the learner hasn't equipped
/// that device yet.
abstract final class KeyboardPromptDismissalStore {
  static const _prefsKey = 'keyboard_prompt_dismissed_steps';

  static Set<String> _dismissed = {};
  static Future<void>? _hydration;
  static bool _hydrated = false;

  static Future<void> initialize() => _hydration = _hydrate();

  /// See [ObservedKeyboardStore.isHydrated].
  static bool get isHydrated => _hydrated;

  /// Completes once the on-disk state is in memory — see
  /// [ObservedKeyboardStore.ready] for why reads must await it.
  static Future<void> get ready => _hydration ??= _hydrate();

  static Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    _dismissed = (prefs.getStringList(_prefsKey) ?? []).toSet();
    _hydrated = true;
  }

  /// Returns the store to its cold-start state — see
  /// [ObservedKeyboardStore.resetForTesting].
  @visibleForTesting
  static void resetForTesting() {
    _hydration = null;
    _dismissed = {};
    _hydrated = false;
  }

  static bool isDismissed(KeyboardPromptStep step, String? languageCode) {
    final key = _key(step, languageCode);
    return key != null && _dismissed.contains(key);
  }

  static Future<void> dismiss(
    KeyboardPromptStep step,
    String? languageCode,
  ) async {
    final key = _key(step, languageCode);
    if (key == null || _dismissed.contains(key)) return;
    _dismissed = {..._dismissed, key};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _dismissed.toList());
  }

  static String? _key(KeyboardPromptStep step, String? languageCode) {
    if (languageCode == null) return null;
    final subtag = primaryLanguageSubtag(languageCode);
    return subtag == null ? null : '${step.name}:$subtag';
  }
}

# keyboard_languages

Flutter plugin: reports the language of every keyboard the user has enabled
on the device, on iOS and Android.

## Why native code

Neither platform's Dart-reachable APIs expose this, so each side calls its
own public system API:

- **Android** — `InputMethodManager.getEnabledInputMethodList()`, then
  `getEnabledInputMethodSubtypeList()` per method, reading each subtype's
  `languageTag`. No permission required.
- **iOS** — `UITextInputMode.activeInputModes`, reading each mode's
  `primaryLanguage`. Also unpermissioned, and includes non-language entries
  (e.g. the emoji keyboard reports `"emoji"`) — the plugin returns those
  as-is rather than filtering, since only the caller knows which entries are
  language-shaped.

## Dart API

```dart
final tags = await KeyboardLanguages.getEnabledLanguageTags();
// e.g. ['en-US', 'es-MX', 'emoji']
```

Returns an empty list wherever the platform call isn't implemented or fails —
callers treat that as "unknown", not "no keyboards", since a real device
always has at least one keyboard enabled.

Used by [`KeyboardLanguageRepo`](../../lib/features/keyboards/keyboard_language_repo.dart)
to answer whether the learner has a keyboard matching their target language
(pangeachat/client#8504). See
[target-language-keyboard.instructions.md](../../.github/instructions/target-language-keyboard.instructions.md).

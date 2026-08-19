# text_input_context

iOS-only Flutter plugin: gives a text field a UIKit `textInputContextIdentifier`,
so iOS restores the keyboard language the user last chose for that field
(across chats and app launches) instead of the device default.

## Why a runtime patch

iOS has no public API to *set* a keyboard language — `UIKeyboardInputMode` is
private and Flutter's `hintLocales` is Android-only
([flutter/flutter#172620](https://github.com/flutter/flutter/issues/172620)).
The one supported lever is `UIResponder.textInputContextIdentifier`: a
responder that returns a non-nil identifier gets its last-used input mode
restored whenever it becomes first responder. Flutter's `FlutterTextInputView`
inherits UIKit's default (nil) and the engine exposes no hook, so the plugin
adds the getter to that class with `class_addMethod` the first time an
identifier is set. `class_addMethod` refuses if the class ever implements the
property itself, in which case the plugin logs and steps aside rather than
fighting the engine.

## Dart API

```dart
// Before the field's EditableText attaches (e.g. from a FocusNode listener
// registered before the field is built):
await TextInputContext.setIdentifier('my-app.composer.es');
// When the field loses focus, so other fields keep the default keyboard:
await TextInputContext.setIdentifier(null);
```

The identifier is cached per engine text input view on first read, so the view
that was focused with an identifier keeps it for its lifetime even after the
identifier is cleared for the next field.

Used by the chat composer in `lib/routes/chat/composer_keyboard_context.dart`
(pangeachat/client#8465).

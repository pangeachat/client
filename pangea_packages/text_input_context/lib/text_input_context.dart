import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Per-field keyboard language persistence for Flutter text input on iOS.
///
/// iOS restores the keyboard language a user last chose for any text field
/// whose `textInputContextIdentifier` it recognises, and persists that across
/// launches — but Flutter's iOS text input view never sets one, and
/// `hintLocales` is Android-only. This plugin patches the engine's text input
/// view to report the identifier set here.
///
/// The identifier applies to the **next** text input connection iOS opens, so
/// call [setIdentifier] before the field's `EditableText` attaches — in
/// practice from a `FocusNode` listener registered before the field is built
/// (listeners fire in registration order and `EditableText` attaches from its
/// own listener on the same node). Clear it with null once the field loses
/// focus so other fields keep the default keyboard; the view that was focused
/// with an identifier keeps it for its own lifetime regardless.
///
/// A no-op everywhere but iOS.
abstract final class TextInputContext {
  static const MethodChannel _channel = MethodChannel(
    'pangea/text_input_context',
  );

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Sets the `textInputContextIdentifier` the next text input view reports,
  /// or clears it with null.
  ///
  /// Resolves to whether the platform patch is in place: false means the
  /// running engine already implements the property itself and the plugin
  /// stepped aside, so keyboard language will not persist.
  static Future<bool> setIdentifier(String? identifier) async {
    if (!_isIOS) return false;
    final installed = await _channel.invokeMethod<bool>('setIdentifier', {
      'identifier': identifier,
    });
    return installed ?? false;
  }
}

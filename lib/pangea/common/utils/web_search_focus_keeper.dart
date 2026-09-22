import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Keeps an open search field focused on web while the page changes around it.
///
/// With the semantics tree on (staging stamps it on for everyone; assistive
/// tech enables it anywhere), Blink drops the field's DOM focus whenever the
/// engine moves its semantic DOM node — which any semantics change around it
/// causes (course tiles loading in or filtering out, map pins animating
/// behind the panel) — closing the text-input connection and unfocusing the
/// field at an arbitrary later moment. No widget structure prevents this
/// (measured in #8581), so while [arm]ed this re-requests focus when it drops
/// without user intent: any pointer-down disarms, and focus landing on a real
/// widget (keyboard traversal) is left alone. Web-only: native has no semantic
/// DOM, and refocusing there would fight system keyboard dismissal.
class WebSearchFocusKeeper {
  final FocusNode focusNode;

  /// Whether the field is still there to refocus — false once its owner is
  /// disposed or has closed the search.
  final bool Function() isSearchOpen;

  bool _armed = false;

  WebSearchFocusKeeper({required this.focusNode, required this.isSearchOpen});

  void arm() {
    if (!kIsWeb || _armed) return;
    _armed = true;
    focusNode.addListener(_onFocusChange);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
  }

  void disarm() {
    if (!_armed) return;
    _armed = false;
    focusNode.removeListener(_onFocusChange);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
  }

  void _onGlobalPointer(PointerEvent event) {
    if (event is PointerDownEvent) disarm();
  }

  void _onFocusChange() {
    if (!_armed || focusNode.hasFocus) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary is! FocusScopeNode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_armed && isSearchOpen() && !focusNode.hasFocus) {
        focusNode.requestFocus();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

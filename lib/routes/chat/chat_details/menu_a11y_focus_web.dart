import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('document')
external JSObject get _document;

/// Focus the first popup-menu item's semantics element directly (#8767).
///
/// The web engine gives `role=menu` popups no focus-on-open behavior (unlike
/// dialogs — see the engine's SemanticRouteBase vs SemanticMenu), and any
/// *framework* focus move that starts while `document.activeElement` is
/// outside the app raises a view-focus event whose fallback focuses the
/// flutter-view host — which throws VoiceOver to the browser window. Focusing
/// the element DOM-first puts activeElement inside the app, so the framework
/// focus request that follows cannot trigger that fallback. No-op when no
/// menu is open.
void domFocusFirstMenuItem() {
  final el = _document.callMethod<JSObject?>(
    'querySelector'.toJS,
    'flt-semantics[role="menuitem"]'.toJS,
  );
  el?.callMethod<JSAny?>('focus'.toJS, {'preventScroll': true}.jsify());
}

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('document')
external JSObject get _document;

/// Focus the first popup-menu item's semantics element the moment it exists
/// in the DOM (#8767).
///
/// Two engine behaviors conspire against `role=menu` popups on web (dialog
/// routes handle both; menus get neither — see SemanticRouteBase vs
/// SemanticMenu):
///
/// 1. The modal barrier's BlockSemantics REMOVES the background's semantics
///    elements — including the node the VoiceOver cursor sits on — in the
///    same flush that adds the menu. If focus reaches the menu even a few
///    hundred ms later, VoiceOver has already escaped to the browser window
///    and ignores it (mutation-traced live).
/// 2. Any *framework* focus move that starts while `document.activeElement`
///    is outside the app raises a view-focus event whose fallback focuses
///    the flutter-view host — the browser-window announcement.
///
/// So: poll from menu open and focus the element DOM-first within a frame of
/// its appearance — one transition VoiceOver follows — which also puts
/// activeElement inside the menu so the framework focus request that follows
/// cannot trigger the host fallback. Gives up quietly if no menu appears.
void domFocusFirstMenuItemWhenReady() {
  var ticks = 0;
  Timer.periodic(const Duration(milliseconds: 16), (timer) {
    if (++ticks > 60) {
      timer.cancel();
      return;
    }
    final el = _document.callMethod<JSObject?>(
      'querySelector'.toJS,
      'flt-semantics[role="menuitem"]'.toJS,
    );
    if (el == null) return;
    timer.cancel();
    el.callMethod<JSAny?>('focus'.toJS, {'preventScroll': true}.jsify());
  });
}

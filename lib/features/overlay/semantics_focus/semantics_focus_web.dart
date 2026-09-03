import 'dart:async';
import 'dart:js_interop';

@JS('document')
external JSObject get _document;

extension type _Document(JSObject _) implements JSObject {
  external _Element? querySelector(String selectors);
}

extension type _Element(JSObject _) implements JSObject {
  external void focus(JSObject options);
}

/// Moves the browser's focus to the `flt-semantics` element the engine renders
/// for the semantics node carrying [identifier], the moment that element
/// exists.
///
/// VoiceOver ignores focus that arrives later than about a frame after the
/// content under its cursor was removed — it escapes to the browser window and
/// stays there (#8769). The framework's own focus request only reaches the
/// semantics tree one frame after the overlay appears, so on web the element is
/// focused directly first; the framework request that follows finds the focus
/// already inside the app and does not hop to the host view.
///
/// Polls at frame rate for about a second, then gives up: the node is added by
/// the same frame that opens the overlay, so the first tick normally finds it.
void focusSemanticsElement(String identifier) {
  var ticks = 0;
  Timer.periodic(const Duration(milliseconds: 16), (timer) {
    final element = _Document(
      _document,
    ).querySelector('flt-semantics[flt-semantics-identifier="$identifier"]');
    if (element != null) {
      element.focus({'preventScroll': true}.jsify()! as JSObject);
      timer.cancel();
    } else if (++ticks >= 60) {
      timer.cancel();
    }
  });
}

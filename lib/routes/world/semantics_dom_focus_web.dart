import 'dart:js_interop';

@JS('document')
external _Document get _document;

extension type _Document(JSObject _) implements JSObject {
  external _Element? get activeElement;
}

extension type _Element(JSObject _) implements JSObject {
  external String get tagName;
  external bool get isConnected;
  external void focus(JSAny? options);
}

/// The semantics element that held DOM focus when an overlay opened, so DOM
/// focus can go straight back to it when the overlay closes (#9049).
///
/// Framework focus alone cannot do this on the web. When the semantics node
/// holding DOM focus is disposed — a menu item unmounting as its menu closes —
/// the engine first parks DOM focus on the `<flutter-view>` root
/// (`FlutterViewManager._transferFocusToViewRoot`), and the framework's
/// restored focus reaches the opener only in a later semantics flush.
/// VoiceOver reads that stop as the whole page, its cursor stays there, and
/// later focus moves do not bring it back. Moving DOM focus to the opener
/// while the overlay's elements still exist means nothing focused is removed,
/// so the engine never parks it.
class SemanticsDomFocus {
  final _Element _element;

  SemanticsDomFocus._(this._element);

  /// The semantics element holding DOM focus now, or null when there is none
  /// to return to — semantics disabled, or focus outside the app.
  static SemanticsDomFocus? capture() {
    final element = _document.activeElement;
    if (element == null || element.tagName.toLowerCase() != 'flt-semantics') {
      return null;
    }
    return SemanticsDomFocus._(element);
  }

  /// Focus the captured element again, if it is still in the page. Call this
  /// before the overlay's elements are removed — as the close starts.
  void restore() {
    if (!_element.isConnected) return;
    _element.focus({'preventScroll': true}.jsify());
  }
}

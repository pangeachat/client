import 'dart:async';
import 'dart:js_interop';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/show_menu_long_press.dart';

@JS('document')
external _DomDocument get _document;

extension type _DomDocument(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
  external _DomElement createElement(String tagName);
  external _DomElement? querySelector(String selectors);
}

extension type _DomEvent(JSObject _) implements JSObject {
  external _DomElement? get target;
  external void preventDefault();
}

extension type _DomElement(JSObject _) implements JSObject {
  external String get id;
  external bool get isConnected;
  external set tabIndex(int value);
  external _DomStyle get style;
  external _DomElement? closest(String selectors);
  external String? getAttribute(String name);
  external void setAttribute(String name, String value);
  external _DomRect getBoundingClientRect();
  external void append(_DomElement child);
  external void remove();
  external void focus(JSAny options);
}

extension type _DomRect(JSObject _) implements JSObject {
  external double get left;
  external double get top;
  external double get width;
  external double get height;
}

extension type _DomStyle(JSObject _) implements JSObject {
  external set cssText(String value);
}

/// A screen reader's "show menu" command (VoiceOver's VO-Shift-M or actions
/// rotor) reaches a web page only as a DOM `contextmenu` event. Flutter's web
/// engine neither publishes long-press or custom semantics actions nor listens
/// for that event, so without this the browser's page menu opens (#8767).
class ShowMenuLongPressBridge {
  /// The DOM id prefix the web engine gives each semantics node's element,
  /// followed by the node id (the engine's `kFlutterSemanticNodePrefix`).
  static const _semanticsNodeIdPrefix = 'flt-semantic-node-';

  /// The attribute the web engine renders a semantics identifier into.
  static const _optedInSelector =
      '[flt-semantics-identifier="${ShowMenuLongPress.semanticsIdentifier}"]';

  static void install() =>
      _document.addEventListener('contextmenu', _onContextMenu.toJS);

  static void _onContextMenu(_DomEvent event) {
    final element = event.target?.closest(_optedInSelector);
    if (element == null) return;

    final nodeId = int.parse(
      element.id.substring(_semanticsNodeIdPrefix.length),
    );
    if (ShowMenuLongPress.perform(nodeId)) {
      event.preventDefault();
      _MenuFocusHandoff.start(element);
      return;
    }
    ErrorHandler.logError(
      e: StateError('Opted-in semantics node has no long-press action'),
      data: {'semanticsNodeId': nodeId},
    );
  }
}

/// Moves the screen reader into the menu the long-press opened.
///
/// The menu's modal barrier removes the opener's element in the same engine
/// update that adds the menu, and the engine only applies focus after that
/// removal. VoiceOver strands on a removed element and ignores focus that
/// arrives later, but it follows a focus move made while the element it
/// leaves still exists. So focus steps from the opener to a stand-in over
/// the opener, which the update does not remove, and on to the menu's first
/// item once it exists. The stand-in sits inside the Flutter view: focus
/// outside the view makes the engine refocus the view itself.
class _MenuFocusHandoff {
  static const _pollInterval = Duration(milliseconds: 16);
  static const _pollLimit = 60;
  static const _flutterViewSelector = 'flutter-view';
  static const _firstMenuItemSelector =
      'flt-semantics[role="menu"] flt-semantics[role="menuitem"]';

  static void start(_DomElement opener) {
    final view = opener.closest(_flutterViewSelector);
    if (view == null) {
      ErrorHandler.logError(
        e: StateError('Opted-in semantics element is outside a Flutter view'),
        data: {'elementId': opener.id},
      );
      return;
    }

    final standIn = _standInFor(opener);
    view.append(standIn);
    _focusWithoutScroll(standIn);

    var polls = 0;
    Timer.periodic(_pollInterval, (timer) {
      final firstItem = _document.querySelector(_firstMenuItemSelector);
      if (firstItem != null) {
        _focusWithoutScroll(firstItem);
      } else if (++polls < _pollLimit) {
        return;
      } else {
        if (opener.isConnected) _focusWithoutScroll(opener);
        ErrorHandler.logError(
          e: StateError('Long-press menu never appeared to take focus'),
          data: {'elementId': opener.id},
        );
      }
      timer.cancel();
      standIn.remove();
    });
  }

  /// An invisible copy of the opener's name and role at its position, so the
  /// screen reader's cursor neither moves nor announces anything new.
  static _DomElement _standInFor(_DomElement opener) {
    final rect = opener.getBoundingClientRect();
    final standIn = _document.createElement('div')
      ..tabIndex = -1
      ..setAttribute('role', opener.getAttribute('role') ?? 'button')
      ..setAttribute('aria-label', opener.getAttribute('aria-label') ?? '');
    standIn.style.cssText =
        'position:fixed;left:${rect.left}px;top:${rect.top}px;'
        'width:${rect.width}px;height:${rect.height}px;'
        'opacity:0;pointer-events:none;';
    return standIn;
  }

  static void _focusWithoutScroll(_DomElement element) =>
      element.focus({'preventScroll': true}.jsify()!);
}

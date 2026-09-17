import 'dart:js_interop';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/show_menu_long_press.dart';

@JS('document')
external _DomEventTarget get _document;

extension type _DomEventTarget(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
}

extension type _DomEvent(JSObject _) implements JSObject {
  external _DomElement? get target;
  external void preventDefault();
}

extension type _DomElement(JSObject _) implements JSObject {
  external String get id;
  external _DomElement? closest(String selectors);
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
      return;
    }
    ErrorHandler.logError(
      e: StateError('Opted-in semantics node has no long-press action'),
      data: {'semanticsNodeId': nodeId},
    );
  }
}

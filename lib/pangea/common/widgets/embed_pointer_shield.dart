/// A transparent DOM layer of our own, laid over an embed so that the browser's
/// mouse events land on Flutter instead of on the embed.
///
/// Flutter web paints its whole scene into a `pointer-events: none` host, and
/// only platform views — a YouTube `<iframe>`, a `<video>` — take browser
/// events. So anything Flutter draws over an embed is invisible to the mouse:
/// the embed swallows clicks meant for the widget on top of it, and a wheel
/// over it scrolls nothing at all, because events inside a cross-origin frame
/// never reach the page. A platform view of our own, composited after the
/// embed, is the only layer that wins those events back; Flutter then hit-tests
/// them as usual, so whatever is painted above the shield receives the gesture.
///
/// Paint it *below* the widgets that should receive the pointer and *above* the
/// embed. It renders nothing off web, where Flutter owns every pixel already.
library;

export 'package:fluffychat/pangea/common/widgets/embed_pointer_shield_stub.dart'
    if (dart.library.js_interop) 'package:fluffychat/pangea/common/widgets/embed_pointer_shield_web.dart';

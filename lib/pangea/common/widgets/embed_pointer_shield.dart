import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
/// embed. Off web Flutter owns every pixel and there is nothing to shield.
///
/// Kept out of semantics: a platform view stays `aria-hidden` while no
/// semantics node is made for it, so the shield never reaches the accessibility
/// tree. Assistive tech activates the embed's own DOM directly, where there is
/// nothing to shield it from.
class EmbedPointerShield extends StatelessWidget {
  const EmbedPointerShield({super.key});

  @override
  Widget build(BuildContext context) => kIsWeb
      // `fromTagName` sizes the element to the slot itself, and the framework
      // keeps the web-only half behind its own conditional import — so this
      // compiles everywhere and needs nothing of ours to be web-specific.
      ? ExcludeSemantics(child: HtmlElementView.fromTagName(tagName: 'div'))
      : const SizedBox.shrink();
}

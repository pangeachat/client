import 'dart:js_interop';

import 'package:flutter/material.dart';

/// The web half of the embed pointer shield — an empty `<div>` platform view.
/// See `embed_pointer_shield.dart` for why it exists and where to paint it.
///
/// It is kept out of semantics: a platform view stays `aria-hidden` while no
/// semantics node is made for it, so the shield never reaches the accessibility
/// tree. Assistive tech activates the embed's own DOM directly, where there is
/// nothing to shield it from.
class EmbedPointerShield extends StatelessWidget {
  const EmbedPointerShield({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: HtmlElementView.fromTagName(
      tagName: 'div',
      // The engine falls back to 100% for an unsized platform view and warns
      // to the console on every mount; sizing it here keeps that quiet.
      onElementCreated: (element) => _StyledElement(element as JSObject).style
        ..width = '100%'
        ..height = '100%',
    ),
  );
}

extension type _StyledElement(JSObject _) implements JSObject {
  external _ElementStyle get style;
}

extension type _ElementStyle(JSObject _) implements JSObject {
  external set width(String value);
  external set height(String value);
}

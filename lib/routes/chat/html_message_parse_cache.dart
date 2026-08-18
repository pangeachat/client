import 'dart:collection';
import 'dart:ui' show TextDirection;

import 'package:html/dom.dart' as dom;

/// Bounded LRU of token-tagged, parsed message DOMs (#8423, stage 3 of
/// #8393).
///
/// [HtmlMessage] re-derived its DOM — token-tag injection with
/// grapheme-level string surgery, then a full HTML parse — on every rebuild
/// of every visible message, though the inputs almost never change between
/// rebuilds. The render walk never mutates the tree, so one parsed DOM can
/// back every rebuild of the same message.
///
/// A hit is only valid while every input that shapes the DOM is unchanged:
/// the raw html (changes on edit), the IDENTITY of the display
/// representation's token list (stable via the wrapper cache and
/// [RepresentationEvent]'s token memo; a different list means new tokens
/// arrived or the display language switched), and the text direction (it
/// drives the RTL tag-inversion pass). Span and widget construction stay
/// per-build — spans hold context-bound gesture recognizers.
class HtmlMessageParseCache {
  HtmlMessageParseCache._();

  static const int maxEntries = 100;

  static final LinkedHashMap<String, _ParsedMessage> _entries = LinkedHashMap();

  static dom.Element get(
    String eventId, {
    required String html,
    required Object? tokensIdentity,
    required TextDirection? textDirection,
    required dom.Element Function() parse,
  }) {
    final cached = _entries.remove(eventId);
    if (cached != null &&
        cached.html == html &&
        identical(cached.tokensIdentity, tokensIdentity) &&
        cached.textDirection == textDirection) {
      // Re-insert to mark as most recently used.
      _entries[eventId] = cached;
      return cached.element;
    }

    final entry = _ParsedMessage(
      html: html,
      tokensIdentity: tokensIdentity,
      textDirection: textDirection,
      element: parse(),
    );
    _entries[eventId] = entry;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return entry.element;
  }

  static void clear() => _entries.clear();
}

class _ParsedMessage {
  final String html;
  final Object? tokensIdentity;
  final TextDirection? textDirection;
  final dom.Element element;

  const _ParsedMessage({
    required this.html,
    required this.tokensIdentity,
    required this.textDirection,
    required this.element,
  });
}

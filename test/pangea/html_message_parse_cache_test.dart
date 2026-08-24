import 'dart:ui' show TextDirection;

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'package:fluffychat/routes/chat/html_message_parse_cache.dart';

/// #8423 — the parse cache must reuse one DOM per unchanged message and
/// re-parse the moment any DOM-shaping input changes: the html (edits), the
/// token-list identity (tokens arriving / display-language switches), or the
/// text direction (RTL tag inversion).
void main() {
  const eventId = r'$msg:fakeServer.notExisting';
  final tokens = <Object>[];

  int parses = 0;
  dom.Element parse(String html) {
    parses++;
    return parser.parse(html).body!;
  }

  setUp(() {
    HtmlMessageParseCache.clear();
    parses = 0;
  });

  dom.Element get({
    String id = eventId,
    String html = 'hola mundo',
    Object? tokensIdentity,
    TextDirection direction = TextDirection.ltr,
  }) => HtmlMessageParseCache.get(
    id,
    html: html,
    tokensIdentity: tokensIdentity ?? tokens,
    textDirection: direction,
    parse: () => parse(html),
  );

  test('unchanged inputs reuse one parsed DOM', () {
    final first = get();
    final second = get();
    expect(identical(first, second), isTrue);
    expect(parses, 1);
  });

  test('an edit (new html) re-parses', () {
    final first = get();
    final second = get(html: 'hola mundo editado');
    expect(identical(first, second), isFalse);
    expect(parses, 2);
    expect(second.text, contains('editado'));
  });

  test('a new token-list identity re-parses, equal contents or not', () {
    final first = get();
    final second = get(tokensIdentity: <Object>[]);
    expect(identical(first, second), isFalse);
    expect(parses, 2);
  });

  test('a direction flip re-parses', () {
    final first = get();
    final second = get(direction: TextDirection.rtl);
    expect(identical(first, second), isFalse);
    expect(parses, 2);
  });

  test('the cache is bounded and evicts least recently used', () {
    final first = get();
    for (var i = 0; i < HtmlMessageParseCache.maxEntries; i++) {
      get(
        id:
            r'$other'
            '$i:fakeServer.notExisting',
        html: 'mensaje $i',
      );
    }
    // eventId was the least recently used entry, so it was evicted and a
    // fresh get must re-parse.
    final refetched = get();
    expect(identical(first, refetched), isFalse);
  });
}

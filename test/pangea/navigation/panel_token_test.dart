import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';

void main() {
  List<PanelToken> right(String url) => parseOpenPanels(Uri.parse(url)).right;
  List<PanelToken> left(String url) => parseOpenPanels(Uri.parse(url)).left;

  group('PanelToken.parse / encode', () {
    test('bare type and type:param', () {
      expect(PanelToken.parse('chats'), const PanelToken('chats'));
      expect(PanelToken.parse('review:!abc'), const PanelToken('review', '!abc'));
    });

    test('only the first colon splits, so room ids survive', () {
      // A full id rides the URL percent-encoded; after decode the colon is back.
      final t = PanelToken.parse('review:!abc%3Ahome.server');
      expect(t, const PanelToken('review', '!abc:home.server'));
    });

    test('malformed types are rejected', () {
      expect(PanelToken.parse(''), isNull);
      expect(PanelToken.parse('Bad'), isNull); // uppercase
      expect(PanelToken.parse('1abc'), isNull); // leading digit
      expect(PanelToken.parse(':param'), isNull); // empty type
    });

    test('encode round-trips a construct whose value has commas and colons', () {
      const token = PanelToken('vocab', '{"lemma":"a,b","type":"verb"}');
      final round = PanelToken.parse(token.encode());
      expect(round, token);
      // The raw encoding must not contain a literal comma or the splitter breaks.
      expect(token.encode().contains(','), isFalse);
    });
  });

  group('parseOpenPanels', () {
    test('empty / missing lists', () {
      expect(right('/chats'), isEmpty);
      expect(left('/chats?right=review:!a'), isEmpty);
      expect(right('/'), isEmpty);
    });

    test('order is preserved across the comma list', () {
      final r = right('/chats?right=analytics:vocab,review:!def');
      expect(r.map((t) => t.type).toList(), ['analytics', 'review']);
      expect(r[0].param, 'vocab');
      expect(r[1].param, '!def');
    });

    test('an encoded comma inside a param does NOT split the list', () {
      // right=vocab:{"lemma":"a,b"} with the value percent-encoded.
      final encoded = Uri.encodeComponent('{"lemma":"a,b"}');
      final r = right('/chats?right=vocab:$encoded');
      expect(r.length, 1);
      expect(r.single.type, 'vocab');
      expect(r.single.param, '{"lemma":"a,b"}');
    });

    test('wrong-column tokens are dropped', () {
      expect(right('/chats?right=room:!a'), isEmpty); // room is a left panel
      expect(left('/chats?left=review:!a'), isEmpty); // review is a right panel
    });

    test('unknown types are dropped', () {
      expect(right('/chats?right=bogus:x,review:!a').map((t) => t.type), ['review']);
    });

    test('duplicate (type, param) pairs are deduped (no duplicate keys)', () {
      final r = right('/chats?right=review:!a,review:!a');
      expect(r.length, 1);
    });

    test('the per-list cap drops the overflow', () {
      final many = List.generate(8, (i) => 'review:!r$i').join(',');
      expect(right('/chats?right=$many').length, 6);
    });
  });
}

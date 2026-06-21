import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';

void main() {
  List<PanelToken> right(String url) => parseOpenPanels(Uri.parse(url)).right;
  List<PanelToken> left(String url) => parseOpenPanels(Uri.parse(url)).left;

  group('PanelToken.parse / encode', () {
    test('bare type and type:param', () {
      expect(PanelToken.parse('chats'), const PanelToken('chats'));
      expect(PanelToken.parse('room:!abc'), const PanelToken('room', '!abc'));
    });

    test('only the first colon splits, so room ids survive', () {
      // A full id rides the URL percent-encoded; after decode the colon is back.
      final t = PanelToken.parse('room:!abc%3Ahome.server');
      expect(t, const PanelToken('room', '!abc:home.server'));
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
      expect(left('/chats?right=analytics:vocab'), isEmpty);
      expect(right('/'), isEmpty);
    });

    test('order is preserved across the comma list', () {
      final r = right('/chats?right=analytics:vocab,settingspage:style');
      expect(r.map((t) => t.type).toList(), ['analytics', 'settingspage']);
      expect(r[0].param, 'vocab');
      expect(r[1].param, 'style');
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
      expect(
        left('/chats?left=analytics:vocab'),
        isEmpty,
      ); // analytics is a right panel
    });

    test('unknown types are dropped', () {
      expect(right('/chats?right=bogus:x,analytics:vocab').map((t) => t.type), [
        'analytics',
      ]);
    });

    test('duplicate (type, param) pairs are deduped (no duplicate keys)', () {
      final r = right('/chats?right=analytics:vocab,analytics:vocab');
      expect(r.length, 1);
    });

    test('the per-list cap drops the overflow', () {
      // analytics has no sibling group, so distinct params all survive to the cap.
      final many = List.generate(8, (i) => 'analytics:t$i').join(',');
      expect(right('/chats?right=$many').length, 6);
    });
  });

  group('parseOpenPanels sibling exclusion', () {
    test('at most one token per sibling group survives (first wins)', () {
      // vocab + grammar both belong to the `detail` group.
      final r = right('/chats?right=vocab:a,grammar:b');
      expect(r.map((t) => t.type).toList(), ['vocab']);
    });

    test('room + session collapse to one live view (liveView group)', () {
      final l = left('/chats?left=room:!a,session:!b');
      expect(l.length, 1);
      expect(l.single.type, 'room');
    });

    test(
      'practice takes over the analytics surface (no analytics beside it)',
      () {
        final r = right('/chats?right=practice:vocab,analytics:vocab');
        expect(r.map((t) => t.type).toList(), ['practice']);
      },
    );
  });

  group('orphan course/coursepage tokens (no map filter)', () {
    test('a course token with no ?m= is dropped (would render blank)', () {
      // course/coursepage read their space from ?m=course:<id>; without it they
      // have nothing to render, so a hand-edited / stale URL degrades to the map.
      expect(left('/?left=course'), isEmpty);
      expect(left('/?left=coursepage:invite'), isEmpty);
    });

    test('a course token WITH its ?m= filter survives', () {
      final l = left('/?m=course:!s&left=course');
      expect(l.map((t) => t.type).toList(), ['course']);
    });

    test('a coursepage survives when its course filter is present', () {
      final l = left('/?m=course:!s&left=course,coursepage:invite');
      expect(l.map((t) => t.type).toList(), ['course', 'coursepage']);
    });
  });
}

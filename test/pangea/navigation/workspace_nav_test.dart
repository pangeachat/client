import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';

void main() {
  Uri u(String s) => Uri.parse(s);

  group('openRight / closeRight', () {
    test('adds a token and round-trips back through the parser', () {
      final loc = WorkspaceNav.openRight(u('/chats'), const PanelToken('review', '!def'));
      expect(parseOpenPanels(u(loc)).right, [const PanelToken('review', '!def')]);
    });

    test('an encoded construct survives the add → URL → parse round-trip', () {
      const token = PanelToken('vocab', '{"lemma":"a,b","type":"verb"}');
      final loc = WorkspaceNav.openRight(u('/chats'), token);
      expect(parseOpenPanels(u(loc)).right.single, token);
    });

    test('atStart blooms a detail to the left of an existing summary', () {
      var loc = WorkspaceNav.openRight(u('/chats'), const PanelToken('analytics', 'vocab'));
      loc = WorkspaceNav.openRight(
        u(loc),
        const PanelToken('vocab', 'hablar'),
        atStart: true,
      );
      expect(parseOpenPanels(u(loc)).right.map((t) => t.type), ['vocab', 'analytics']);
    });

    test('adding an existing token is idempotent (deduped)', () {
      var loc = WorkspaceNav.openRight(u('/chats'), const PanelToken('review', '!a'));
      loc = WorkspaceNav.openRight(u(loc), const PanelToken('review', '!a'));
      expect(parseOpenPanels(u(loc)).right.length, 1);
    });

    test('close removes the token; the key disappears when the list empties', () {
      final opened = WorkspaceNav.openRight(u('/chats'), const PanelToken('review', '!a'));
      final closed = WorkspaceNav.closeRight(u(opened), const PanelToken('review', '!a'));
      expect(parseOpenPanels(u(closed)).right, isEmpty);
      expect(closed, '/chats'); // no dangling ?right=
    });
  });

  group('preserves the rest of the URL', () {
    test('an unrelated query param is kept verbatim', () {
      final loc = WorkspaceNav.openRight(
        u('/courses/!s?activity=abc'),
        const PanelToken('analytics', 'sessions'),
      );
      final parsed = u(loc);
      expect(parsed.queryParameters['activity'], 'abc');
      expect(parseOpenPanels(parsed).right, [const PanelToken('analytics', 'sessions')]);
      expect(parsed.path, '/courses/!s');
    });

    test('the path is preserved', () {
      final loc = WorkspaceNav.openRight(u('/rooms/!abc'), const PanelToken('review', '!def'));
      expect(u(loc).path, '/rooms/!abc');
    });
  });

  group('setRight replaces the whole list (metric switch)', () {
    test('drops the old analytics/detail tokens and seats one summary', () {
      var loc = WorkspaceNav.openRight(u('/chats'), const PanelToken('analytics', 'vocab'));
      loc = WorkspaceNav.openRight(u(loc), const PanelToken('vocab', 'hablar'), atStart: true);
      loc = WorkspaceNav.setRight(u(loc), [const PanelToken('analytics', 'grammar')]);
      expect(parseOpenPanels(u(loc)).right, [const PanelToken('analytics', 'grammar')]);
    });
  });
}

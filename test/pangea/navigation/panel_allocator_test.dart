import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_registry.dart';
import 'package:fluffychat/widgets/layouts/panel_allocator.dart';

void main() {
  PanelDef def(String type) => PanelRegistry.defs[type]!;

  WorkspaceLayout run({
    double viewport = 1600,
    bool isColumnMode = true,
    List<String> left = const [],
    List<String> right = const [],
  }) =>
      PanelAllocator.allocate(
        viewport: viewport,
        isColumnMode: isColumnMode,
        left: left.map(def).toList(),
        right: right.map(def).toList(),
      );

  // No two full panels may overlap — the core invariant.
  void expectNoOverlap(WorkspaceLayout l) {
    final fulls = [...l.left, ...l.right]
        .where((s) => s.vis == PanelVis.full)
        .toList()
      ..sort((a, b) => a.left.compareTo(b.left));
    for (var i = 1; i < fulls.length; i++) {
      expect(fulls[i - 1].left + fulls[i - 1].width,
          lessThanOrEqualTo(fulls[i].left + 0.01),
          reason: 'panel $i overlaps its predecessor');
    }
  }

  group('greedy up to ideal, map fills the rest', () {
    test('a single right summary docks at the right edge behind the gutter', () {
      final l = run(right: ['analytics']);
      expect(l.right.single.width, 488);
      expect(l.right.single.left, 1600 - 88 - 488); // 1024
      expect(l.mapRightOverlay, 576); // 488 + gutter 88
      expect(l.mapLeftOverlay, 73); // rail only, no left panel
      expect(l.clusterVisible, isTrue);
    });

    test('a single left chat caps at 720 and the map shows beyond it', () {
      final l = run(left: ['room']);
      expect(l.right, isEmpty);
      expect(l.left.single.width, 720); // capped at ideal, not the whole screen
      expect(l.left.single.left, 73);
      expect(l.mapLeftOverlay, 793); // rail + 720
      expect(l.mapRightOverlay, 0); // no right panels, no gutter
    });

    test('summary + detail tile as two right cards, detail to the left', () {
      final l = run(right: ['vocab', 'analytics']); // [detail, summary]
      expect(l.right[0].width, 488);
      expect(l.right[1].width, 488);
      expect(l.right[1].left, 1600 - 88 - 488); // summary at the edge
      expectNoOverlap(l);
      expect(l.mapRightOverlay, 488 * 2 + 16 + 88); // both cards + gap + gutter
    });
  });

  group('shared-width compression (replaces the old slide-over)', () {
    test('a chat + a summary on a tight viewport both stay open, compressed', () {
      final l = run(viewport: 1100, left: ['room'], right: ['analytics']);
      expect(l.left.single.vis, PanelVis.full);
      expect(l.right.single.vis, PanelVis.full);
      // neither drops below its floor...
      expect(l.left.single.width, greaterThanOrEqualTo(360));
      expect(l.right.single.width, greaterThanOrEqualTo(360));
      // ...and they don't overlap.
      expectNoOverlap(l);
    });

    test('the lowest-priority panel folds away (not drawn) when reasonable '
        "mins can't all be met", () {
      // Three right panels can't all honor their reasonable-min in this budget,
      // so the lowest-priority one folds out of the layout entirely (no stripe).
      final l = run(viewport: 1161, right: ['review', 'vocab', 'analytics']);
      final folded = l.right.where((s) => s.vis == PanelVis.hidden).toList();
      expect(folded.length, 1);
      // analytics has the lowest priority (40 < vocab 50 < review 70).
      expect(l.right[2].vis, PanelVis.hidden);
      expect(l.right[0].vis, PanelVis.full);
      expect(l.right[1].vis, PanelVis.full);
      expect(folded.single.width, 0); // folded slots carry no width
      expectNoOverlap(l);
    });

    test('a master/detail pair folds to one panel below its reasonable-min', () {
      // A live chat (room) beside the chat list, on a viewport too narrow to
      // honor both reasonable-mins (480 + 340 + chrome): the lower-priority list
      // folds away and the room — highest priority — keeps the column and its
      // session. Closing the room reveals the list (back-to-master).
      final l = run(viewport: 900, left: ['chats', 'room']);
      expect(l.left[1].vis, PanelVis.full); // room (priority 80) stays
      expect(l.left[0].vis, PanelVis.hidden); // chats (priority 30) folds
      // The surviving room is "folded over" its master → its close is a `←`.
      expect(l.left[1].foldedOver, isTrue);
      expectNoOverlap(l);
    });

    test('coexisting (unfolded) panels are NOT foldedOver — their close is X', () {
      // Wide enough for chat list + room to both stay full: neither folds, so
      // neither is folded-over (closing either reveals the map, not a master).
      final l = run(viewport: 1920, left: ['chats', 'room']);
      expect(l.left[0].vis, PanelVis.full);
      expect(l.left[1].vis, PanelVis.full);
      expect(l.left.every((s) => !s.foldedOver), isTrue);
    });
  });

  group('non-overlap holds across viewports', () {
    test('chat + summary never overlap from tight to wide', () {
      for (final viewport in [900.0, 1100.0, 1334.0, 1600.0, 1920.0]) {
        expectNoOverlap(run(viewport: viewport, left: ['room'], right: ['analytics']));
      }
    });
  });

  group('narrow mode is the degenerate case', () {
    test('seats the highest-priority panel; the rest hide; rail goes to zero', () {
      final l = run(viewport: 400, isColumnMode: false, left: ['chats'], right: ['analytics']);
      expect(l.railWidth, 0);
      expect(l.right.single.vis, PanelVis.full); // analytics (40) > chats (30)
      expect(l.right.single.width, 400);
      expect(l.left.single.vis, PanelVis.hidden);
      expect(l.clusterVisible, isFalse);
    });

    test('no panels: the cluster shows over a full-width map', () {
      final l = run(viewport: 400, isColumnMode: false);
      expect(l.clusterVisible, isTrue);
      expect(l.mapLeftOverlay, 0);
    });
  });

  group('exclusive panel holds the screen', () {
    test('an exclusive panel takes the content area and hides the rest', () {
      const exclusiveDef = PanelDef(
        column: PanelColumn.left,
        minWidth: 360,
        idealWidth: 720,
        priority: 90,
        exclusive: true,
      );
      final l = PanelAllocator.allocate(
        viewport: 1600,
        isColumnMode: true,
        left: [exclusiveDef],
        right: [PanelRegistry.defs['analytics']!],
      );
      expect(l.left.single.vis, PanelVis.full);
      expect(l.left.single.width, 1600 - 73); // whole content area
      expect(l.right.single.vis, PanelVis.hidden);
      expect(l.clusterVisible, isFalse);
    });
  });
}

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
    int? focusHint,
  }) => PanelAllocator.allocate(
    viewport: viewport,
    isColumnMode: isColumnMode,
    left: left.map(def).toList(),
    right: right.map(def).toList(),
    focusHint: focusHint,
  );

  // No two full panels may overlap — the core invariant.
  void expectNoOverlap(WorkspaceLayout l) {
    final fulls =
        [...l.left, ...l.right].where((s) => s.vis == PanelVis.full).toList()
          ..sort((a, b) => a.left.compareTo(b.left));
    for (var i = 1; i < fulls.length; i++) {
      expect(
        fulls[i - 1].left + fulls[i - 1].width,
        lessThanOrEqualTo(fulls[i].left + 0.01),
        reason: 'panel $i overlaps its predecessor',
      );
    }
  }

  group('greedy up to ideal, map fills the rest', () {
    test(
      'a single right summary docks at the right edge behind the gutter',
      () {
        final l = run(right: ['analytics']);
        expect(l.right.single.width, 488);
        expect(l.right.single.left, 1600 - 88 - 488); // 1024
        expect(l.mapRightOverlay, 576); // 488 + gutter 88
        expect(l.mapLeftOverlay, 73); // rail only, no left panel
        expect(l.clusterVisible, isTrue);
      },
    );

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
    test(
      'a chat + a summary on a tight viewport both stay open, compressed',
      () {
        final l = run(viewport: 1100, left: ['room'], right: ['analytics']);
        expect(l.left.single.vis, PanelVis.full);
        expect(l.right.single.vis, PanelVis.full);
        // neither drops below its floor...
        expect(l.left.single.width, greaterThanOrEqualTo(360));
        expect(l.right.single.width, greaterThanOrEqualTo(360));
        // ...and they don't overlap.
        expectNoOverlap(l);
      },
    );

    test('the parent (master) folds away (not drawn) when reasonable '
        "mins can't all be met", () {
      // Three right panels can't all honor their reasonable-min in this budget.
      // vocab's parent is analytics, so under pressure analytics (the master)
      // folds behind vocab (its detail); review is an unrelated root and stays.
      final l = run(viewport: 1161, right: ['review', 'vocab', 'analytics']);
      final folded = l.right.where((s) => s.vis == PanelVis.hidden).toList();
      expect(folded.length, 1);
      expect(
        l.right[2].vis,
        PanelVis.hidden,
      ); // analytics (vocab's parent) folds
      expect(l.right[0].vis, PanelVis.full); // review
      expect(l.right[1].vis, PanelVis.full); // vocab keeps the column
      expect(folded.single.width, 0); // folded slots carry no width
      expectNoOverlap(l);
    });

    test('a master/detail pair folds to one panel below its reasonable-min', () {
      // A live chat (room) beside the chat list, on a viewport too narrow to
      // honor both reasonable-mins (480 + 340 + chrome): room's parent is chats,
      // so the chat list (master) folds away and the room (its detail) keeps the
      // column and its session. Closing the room reveals the list (back-to-master).
      final l = run(viewport: 900, left: ['chats', 'room']);
      expect(l.left[1].vis, PanelVis.full); // room (chats's detail) stays
      expect(l.left[0].vis, PanelVis.hidden); // chats (room's parent) folds
      // The surviving room is "folded over" its master → its close is a `←`.
      expect(l.left[1].foldedOver, isTrue);
      expectNoOverlap(l);
    });

    test(
      'coexisting (unfolded) panels are NOT foldedOver — their close is X',
      () {
        // Wide enough for chat list + room to both stay full: neither folds, so
        // neither is folded-over (closing either reveals the map, not a master).
        final l = run(viewport: 1920, left: ['chats', 'room']);
        expect(l.left[0].vis, PanelVis.full);
        expect(l.left[1].vis, PanelVis.full);
        expect(l.left.every((s) => !s.foldedOver), isTrue);
      },
    );
  });

  group('always-single-window details fold their master unconditionally '
      '(#7145)', () {
    test('the settings page always folds the menu behind it — one window, '
        'even when both would fit', () {
      // openSettings seats the page in front of the menu: [settingspage,
      // settings]. The page is flagged foldsParentAlways, so the menu folds
      // behind it BEFORE any width pressure — even on a wide viewport where
      // both reasonable-mins fit. The result reads as one window (the page)
      // with a back that reveals the menu, like the narrow layout, never a
      // redundant second side tab.
      final l = run(viewport: 1920, right: ['settingspage', 'settings']);
      expect(l.right[0].vis, PanelVis.full); // settingspage holds the column
      expect(l.right[1].vis, PanelVis.hidden); // settings menu folds behind it
      expect(l.right[1].width, 0); // folded slots carry no width
      // The surviving page is folded-over its master → its close is a `←` back.
      expect(l.right[0].foldedOver, isTrue);
      expectNoOverlap(l);
    });

    test('the page holds the column at the same width the menu had — no '
        'resize or close/back jump when drilling in (#7146)', () {
      // The page replaces the folded menu in the same slot, so the two must be
      // the same width. An unequal ideal (520 menu vs 600 page) resized the
      // panel and shifted the leading close/back icon when opening a sub-page.
      final menuOnly = run(viewport: 1920, right: ['settings']);
      final withPage = run(viewport: 1920, right: ['settingspage', 'settings']);
      expect(withPage.right[0].width, menuOnly.right.single.width);
      // Guard the defs directly so they can't silently drift apart again.
      expect(def('settingspage').idealWidth, def('settings').idealWidth);
    });

    test('an ordinary master/detail pair (analytics + vocab) still coexists '
        'when width allows — the fold is scoped to flagged details', () {
      // Same wide viewport: vocab is analytics's detail but NOT
      // foldsParentAlways, so with room for both reasonable-mins they tile
      // side by side and neither is folded-over (closing either reveals the
      // map, not a master).
      final l = run(viewport: 1920, right: ['vocab', 'analytics']);
      expect(l.right[0].vis, PanelVis.full); // vocab
      expect(l.right[1].vis, PanelVis.full); // analytics
      expect(l.right.every((s) => !s.foldedOver), isTrue);
      expectNoOverlap(l);
    });
  });

  group('left↔right parity collapse (#7088)', () {
    test(
      'a lone right summary yields (collapses) instead of being overlapped',
      () {
        // course + room (independent left panels) + the analytics summary can't
        // all honor their hard mins in this column-mode budget, and analytics
        // has no same-column child to fold behind. It is the lowest priority
        // (analytics 40 < course 60 < room 80), so it collapses to make room
        // rather than being overlapped by the left column.
        final l = run(
          viewport: 1200,
          left: ['course', 'room'],
          right: ['analytics'],
        );
        expect(l.right.single.vis, PanelVis.hidden); // analytics yields
        expect(l.left[0].vis, PanelVis.full); // course
        expect(l.left[1].vis, PanelVis.full); // room
        expectNoOverlap(l);
      },
    );

    test('the collapse is symmetric across columns (parity)', () {
      const lo = PanelDef(
        type: 'lo',
        column: PanelColumn.left,
        minWidth: 360,
        idealWidth: 720,
        priority: 20,
      );
      const hi = PanelDef(
        type: 'hi',
        column: PanelColumn.left,
        minWidth: 360,
        idealWidth: 720,
        priority: 80,
      );
      // Two independent panels, one per column, on a budget too tight for both
      // hard mins: the LOWER-priority one collapses regardless of its column.
      final rightLo = PanelAllocator.allocate(
        viewport: 850,
        isColumnMode: true,
        left: [hi],
        right: [lo],
      );
      expect(rightLo.right.single.vis, PanelVis.hidden); // lo (right) yields
      expect(rightLo.left.single.vis, PanelVis.full); // hi (left) stays

      final leftLo = PanelAllocator.allocate(
        viewport: 850,
        isColumnMode: true,
        left: [lo],
        right: [hi],
      );
      expect(leftLo.left.single.vis, PanelVis.hidden); // lo (left) yields
      expect(leftLo.right.single.vis, PanelVis.full); // hi (right) stays
    });

    test('the just-opened (focus) panel is never the one collapsed', () {
      const lo = PanelDef(
        type: 'lo',
        column: PanelColumn.left,
        minWidth: 360,
        idealWidth: 720,
        priority: 20,
      );
      const hi = PanelDef(
        type: 'hi',
        column: PanelColumn.left,
        minWidth: 360,
        idealWidth: 720,
        priority: 80,
      );
      // all = [hi(left,0), lo(right,1)]; the user just opened lo (focusHint=1).
      // Even though lo is the lower priority, it must survive — the higher-
      // priority hi yields, so opening lo is not a visible no-op.
      final l = PanelAllocator.allocate(
        viewport: 850,
        isColumnMode: true,
        left: [hi],
        right: [lo],
        focusHint: 1,
      );
      expect(l.right.single.vis, PanelVis.full); // lo kept (focused)
      expect(l.left.single.vis, PanelVis.hidden); // hi yields despite priority
    });
  });

  group('non-overlap holds across viewports', () {
    test('chat + summary never overlap from tight to wide', () {
      for (final viewport in [900.0, 1100.0, 1334.0, 1600.0, 1920.0]) {
        expectNoOverlap(
          run(viewport: viewport, left: ['room'], right: ['analytics']),
        );
      }
    });
  });

  group('narrow mode is the degenerate case', () {
    test(
      'seats the highest-priority panel; the rest hide; rail goes to zero',
      () {
        final l = run(
          viewport: 400,
          isColumnMode: false,
          left: ['chats'],
          right: ['analytics'],
        );
        expect(l.railWidth, 0);
        expect(
          l.right.single.vis,
          PanelVis.full,
        ); // analytics (40) > chats (30)
        expect(l.right.single.width, 400);
        expect(l.left.single.vis, PanelVis.hidden);
        expect(l.clusterVisible, isFalse);
      },
    );

    test('no panels: the cluster shows over a full-width map', () {
      final l = run(viewport: 400, isColumnMode: false);
      expect(l.clusterVisible, isTrue);
      expect(l.mapLeftOverlay, 0);
    });

    test('seats the active leaf — a child shows over its open parent', () {
      // chats (parent) + room (its child) open: the room is the leaf (chats is
      // its parent), so the room shows and the list folds behind it — straight
      // from the tree, no recency.
      final l = run(
        viewport: 400,
        isColumnMode: false,
        left: ['chats', 'room'],
      );
      expect(l.left[1].vis, PanelVis.full); // room (leaf)
      expect(l.left[0].vis, PanelVis.hidden); // chats (room's parent)
    });

    test('a child shows over its parent even across columns (session)', () {
      // session's parent is the right-column analytics list; with both open the
      // session is the leaf and is focusable over its list.
      final l = run(
        viewport: 400,
        isColumnMode: false,
        left: ['session'],
        right: ['analytics'],
      );
      expect(l.left.single.vis, PanelVis.full); // session (leaf)
      expect(
        l.right.single.vis,
        PanelVis.hidden,
      ); // analytics (session's parent)
    });

    test('a child wins focus over a higher-priority open parent', () {
      // A synthetic parent with HIGHER priority than its child: the leaf rule
      // still seats the child, proving focus is the tree (leaf), not priority.
      const parent = PanelDef(
        type: 'p',
        column: PanelColumn.left,
        minWidth: 360,
        idealWidth: 720,
        priority: 99,
      );
      const child = PanelDef(
        type: 'c',
        column: PanelColumn.left,
        parent: 'p',
        minWidth: 360,
        idealWidth: 720,
        priority: 10,
      );
      final l = PanelAllocator.allocate(
        viewport: 400,
        isColumnMode: false,
        left: [parent, child],
        right: const [],
      );
      expect(l.left[1].vis, PanelVis.full); // child, despite priority 10
      expect(l.left[0].vis, PanelVis.hidden); // parent, despite priority 99
    });

    test('among independent leaves the highest priority wins (cold link)', () {
      // No focusHint (a cold deep link / refresh): fall back to the tree. room
      // (no open chats parent) + analytics (no open child) are both leaves; with
      // no tree relation to break the tie, priority decides: room 80 > 40.
      final l = run(
        viewport: 400,
        isColumnMode: false,
        left: ['room'],
        right: ['analytics'],
      );
      expect(l.left.single.vis, PanelVis.full); // room
      expect(l.right.single.vis, PanelVis.hidden); // analytics
    });

    test(
      'focusHint (most-recently-opened) overrides priority and the leaf rule',
      () {
        // The regression guard for "open a panel over a chat = visible no-op":
        // entries are [room, analytics] (merged left..right), room out-ranks
        // analytics (80 > 40) and analytics is a leaf too — but the user just
        // opened analytics, so focusHint=1 must seat it over the room.
        final l = run(
          viewport: 400,
          isColumnMode: false,
          left: ['room'],
          right: ['analytics'],
          focusHint: 1,
        );
        expect(l.right.single.vis, PanelVis.full); // analytics (just opened)
        expect(l.left.single.vis, PanelVis.hidden); // room, despite priority 80

        // Opening the room last focuses it instead.
        final l2 = run(
          viewport: 400,
          isColumnMode: false,
          left: ['room'],
          right: ['analytics'],
          focusHint: 0,
        );
        expect(l2.left.single.vis, PanelVis.full);
        expect(l2.right.single.vis, PanelVis.hidden);
      },
    );
  });

  group('registry integrity', () {
    test('every def.type matches its map key', () {
      PanelRegistry.defs.forEach((key, d) => expect(d.type, key));
    });

    test('every parent names a known type', () {
      for (final d in PanelRegistry.defs.values) {
        if (d.parent != null) {
          expect(
            PanelRegistry.defs.containsKey(d.parent),
            isTrue,
            reason: '${d.type} → unknown parent ${d.parent}',
          );
        }
      }
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

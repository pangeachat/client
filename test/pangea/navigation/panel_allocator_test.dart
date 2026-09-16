import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_registry.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/widgets/layouts/panel_allocator.dart';

void main() {
  WorkspaceLayout run({
    double viewport = 1600,
    bool isColumnMode = true,
    List<PanelTypesEnum> left = const [],
    List<PanelTypesEnum> right = const [],
    int? focusHint,
  }) => PanelAllocator.allocate(
    viewport: viewport,
    isColumnMode: isColumnMode,
    left: left.map((t) => t.def).toList(),
    right: right.map((t) => t.def).toList(),
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
        final l = run(right: [PanelTypesEnum.analytics]);
        // The tool-family ideal (#7572) — one width for the whole right column.
        const w = PanelWidths.toolIdeal;
        expect(l.right.single.width, w);
        expect(l.right.single.left, 1600 - 88 - w);
        expect(l.mapRightOverlay, w + 88); // card + gutter
        expect(l.mapLeftOverlay, 73); // rail only, no left panel
        expect(l.clusterVisible, isTrue);
      },
    );

    test('a single left chat caps at 720 and the map shows beyond it', () {
      final l = run(left: [PanelTypesEnum.room]);
      expect(l.right, isEmpty);
      expect(l.left.single.width, 720); // capped at ideal, not the whole screen
      expect(l.left.single.left, 73);
      expect(l.mapLeftOverlay, 793); // rail + 720
      // The camera overlay models PANEL coverage only — the cluster floats
      // over the bare map, so its (always-reserved) gutter is not part of it.
      expect(l.mapRightOverlay, 0);
    });

    test('summary + detail tile as two right cards, detail to the left', () {
      final l = run(
        right: [PanelTypesEnum.analytics, PanelTypesEnum.vocab],
      ); // master-first [summary, detail]
      const w = PanelWidths.toolIdeal;
      expect(l.right[0].width, w);
      expect(l.right[1].width, w);
      expect(l.right[0].left, 1600 - 88 - w); // summary (master) at the edge
      expect(l.right[1].left, 1600 - 88 - w - 16 - w); // detail to its left
      expectNoOverlap(l);
      expect(l.mapRightOverlay, w * 2 + 16 + 88); // both cards + gap + gutter
    });
  });

  group('shared-width compression (replaces the old slide-over)', () {
    test(
      'a chat + a summary on a tight viewport both stay open, compressed',
      () {
        final l = run(
          viewport: 1100,
          left: [PanelTypesEnum.room],
          right: [PanelTypesEnum.analytics],
        );
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
      final l = run(
        viewport: 1161,
        right: [
          PanelTypesEnum.review,
          PanelTypesEnum.analytics,
          PanelTypesEnum.vocab,
        ],
      );
      final folded = l.right.where((s) => s.vis == PanelVis.hidden).toList();
      expect(folded.length, 1);
      expect(
        l.right[1].vis,
        PanelVis.hidden,
      ); // analytics (vocab's parent) folds
      expect(l.right[0].vis, PanelVis.full); // review
      expect(l.right[2].vis, PanelVis.full); // vocab keeps the column
      expect(folded.single.width, 0); // folded slots carry no width
      expectNoOverlap(l);
    });

    test('a master/detail pair folds to one panel below its reasonable-min', () {
      // A live chat (room) beside the chat list, on a viewport too narrow to
      // honor both reasonable-mins (480 + 340 + chrome): room's parent is chats,
      // so the chat list (master) folds away and the room (its detail) keeps the
      // column and its session. Closing the room reveals the list (back-to-master).
      final l = run(
        viewport: 900,
        left: [PanelTypesEnum.chats, PanelTypesEnum.room],
      );
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
        final l = run(
          viewport: 1920,
          left: [PanelTypesEnum.chats, PanelTypesEnum.room],
        );
        expect(l.left[0].vis, PanelVis.full);
        expect(l.left[1].vis, PanelVis.full);
        expect(l.left.every((s) => !s.foldedOver), isTrue);
      },
    );
  });

  group('a detail opens beside its master when width allows (#7467, no '
      'always-fold)', () {
    test('the settings page tiles beside its menu on a wide viewport — folds '
        'only under width pressure, like any master/detail pair', () {
      // Master-first [settings, settingspage]. With room for both
      // reasonable-mins, the menu (master) holds the edge and the page blooms
      // to its left; neither folds, so each closes to the map — the same fit
      // test as a course page (was the #7145 always-fold, removed).
      final l = run(
        viewport: 1920,
        right: [PanelTypesEnum.settings, PanelTypesEnum.settingspage],
      );
      expect(l.right[0].vis, PanelVis.full); // settings menu (master), at edge
      expect(l.right[1].vis, PanelVis.full); // settingspage, to its left
      expect(l.right.every((s) => !s.foldedOver), isTrue);
      expect(l.right[0].left, greaterThan(l.right[1].left)); // master at edge
      expectNoOverlap(l);
    });

    test('the menu + page are the same width so nothing resizes or jumps the '
        'close/back icon when they fold under pressure (#7146)', () {
      final menuOnly = run(viewport: 1920, right: [PanelTypesEnum.settings]);
      expect(
        PanelTypesEnum.settingspage.def.idealWidth,
        PanelTypesEnum.settings.def.idealWidth,
      );
      expect(
        PanelTypesEnum.settings.def.idealWidth,
        menuOnly.right.single.width,
      );
    });

    test('an ordinary master/detail pair (analytics + vocab) also coexists '
        'when width allows', () {
      final l = run(
        viewport: 1920,
        right: [PanelTypesEnum.analytics, PanelTypesEnum.vocab],
      );
      expect(l.right[0].vis, PanelVis.full); // analytics (master), at edge
      expect(l.right[1].vis, PanelVis.full); // vocab, to its left
      expect(l.right.every((s) => !s.foldedOver), isTrue);
      expectNoOverlap(l);
    });
  });

  group('left↔right parity collapse (#7088)', () {
    test(
      'a lone right summary yields (collapses) instead of being overlapped',
      () {
        // One panel per column, so NOTHING can fold (a fold needs two panels in
        // one column) — the only configuration that still reaches Tier 2 now
        // that the fold is positional (#9030). Just past the two-column
        // breakpoint their hard mins (360 + 360) overflow the budget, so the
        // lowest-priority panel (analytics 40 < room 80) collapses rather than
        // being overlapped by the left column.
        final l = run(
          viewport: 860,
          left: [PanelTypesEnum.room],
          right: [PanelTypesEnum.analytics],
        );
        expect(l.right.single.vis, PanelVis.hidden); // analytics yields
        expect(l.left.single.vis, PanelVis.full); // room
        expectNoOverlap(l);
      },
    );

    test('the collapse is symmetric across columns (parity)', () {
      // lowest priority panel
      const lo = ChatsPanelDef(minWidth: 360, idealWidth: 720);

      // highest priority panel
      const hi = RoomPanelDef(minWidth: 360, idealWidth: 720);

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
      // lowest priority panel
      const lo = ChatsPanelDef(minWidth: 360, idealWidth: 720);

      // highest priority panel
      const hi = RoomPanelDef(minWidth: 360, idealWidth: 720);

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
          run(
            viewport: viewport,
            left: [PanelTypesEnum.room],
            right: [PanelTypesEnum.analytics],
          ),
        );
      }
    });
  });

  group('the cluster gutter is reserved on every column layout', () {
    // The cluster is persistent chrome on every non-exclusive column layout,
    // so its gutter must come out of the budget even with an EMPTY right
    // column — the regression here was a left panel growing to its ideal and
    // sliding under the cluster at just-past-breakpoint viewports.
    test('a lone left panel compresses at the gutter instead of sliding '
        'under the cluster', () {
      final l = run(viewport: 860, left: [PanelTypesEnum.course]);
      expect(l.clusterVisible, isTrue);
      expect(l.left.single.left, 73);
      expect(l.left.single.width, 860 - 73 - 88); // 699, not ideal 720
      expect(
        l.left.single.left + l.left.single.width,
        860 - PanelAllocator.clusterGutter,
      );
      expect(l.mapRightOverlay, 0); // camera overlay stays panel-only
    });

    test('no full left slot ever crosses viewport - clusterGutter', () {
      const combos = [
        [PanelTypesEnum.course],
        [PanelTypesEnum.chats, PanelTypesEnum.room],
        [PanelTypesEnum.room, PanelTypesEnum.course],
      ];
      for (final viewport in [
        841.0,
        860.0,
        902.0,
        950.0,
        1100.0,
        1298.0,
        1600.0,
      ]) {
        for (final left in combos) {
          final l = run(viewport: viewport, left: left);
          for (final s in l.left.where((s) => s.vis == PanelVis.full)) {
            expect(
              s.left + s.width,
              lessThanOrEqualTo(viewport - PanelAllocator.clusterGutter + 0.01),
              reason: '$left at $viewport crosses the cluster gutter',
            );
          }
        }
      }
    });

    test('the fold band includes the gutter: chats+room folds where the pair '
        'would otherwise reach under the cluster', () {
      // 950 - 73 - 88 = 789 of content < the pair's reasonable need (836),
      // so the master folds — without the reservation they would coexist
      // with the room flush against the viewport edge, burying the cluster.
      final l = run(
        viewport: 950,
        left: [PanelTypesEnum.chats, PanelTypesEnum.room],
      );
      expect(l.left[0].vis, PanelVis.hidden); // chats folds
      expect(l.left[1].vis, PanelVis.full);
      expect(l.left[1].width, 720); // room takes its ideal in the freed span
      expect(l.left[1].foldedOver, isTrue);
    });

    test('every registry def keeps compression headroom (ideal > min)', () {
      // The allocator's compression branch divides by total headroom; a def
      // with ideal == min across the board would skip compression entirely
      // and let columns overlap. Data invariant, guarded here.
      for (final t in PanelTypesEnum.values) {
        final d = t.def;
        expect(
          d.idealWidth,
          greaterThan(d.minWidth),
          reason: '${d.type} has no compression headroom',
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
          left: [PanelTypesEnum.chats],
          right: [PanelTypesEnum.analytics],
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
        left: [PanelTypesEnum.chats, PanelTypesEnum.room],
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
        left: [PanelTypesEnum.session],
        right: [PanelTypesEnum.analytics],
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
      const parent = ChatsPanelDef(
        minWidth: 360,
        idealWidth: 720,
        priority: 99,
      );
      const child = RoomPanelDef(minWidth: 360, idealWidth: 720, priority: 10);
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
        left: [PanelTypesEnum.room],
        right: [PanelTypesEnum.analytics],
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
          left: [PanelTypesEnum.room],
          right: [PanelTypesEnum.analytics],
          focusHint: 1,
        );
        expect(l.right.single.vis, PanelVis.full); // analytics (just opened)
        expect(l.left.single.vis, PanelVis.hidden); // room, despite priority 80

        // Opening the room last focuses it instead.
        final l2 = run(
          viewport: 400,
          isColumnMode: false,
          left: [PanelTypesEnum.room],
          right: [PanelTypesEnum.analytics],
          focusHint: 0,
        );
        expect(l2.left.single.vis, PanelVis.full);
        expect(l2.right.single.vis, PanelVis.hidden);
      },
    );
  });

  group('registry integrity', () {
    test('every parent names a known type', () {
      for (final t in PanelTypesEnum.values) {
        final d = t.def;
        if (d.parent != null) {
          expect(
            PanelTypesEnum.values.contains(d.parent),
            isTrue,
            reason: '${d.type} → unknown parent ${d.parent}',
          );
        }
      }
    });

    test('the activity panel is a left-column liveView map-content root (#7385)', () {
      final activity = PanelTypesEnum.activity.def;
      // A root master like `course` (opens from the map/course, no parent) — so it
      // never folds behind anything and is the narrow-focus leaf when open.
      expect(activity.column, PanelColumn.left);
      expect(activity.parent, isNull);
      // Claims the single live view: a `liveView` sibling of room/session, so
      // opening an activity drops any open chat and vice versa.
      expect(activity.siblingGroups, contains('liveView'));
      // Map content → a bottom sheet on a narrow screen, like a course.
      expect(activity.mapContent, isTrue);
      // Sized like a `room` (the live work surface) so it never shrinks past the
      // chat's floor — the bug #7385 fixed by pulling it into the allocator budget.
      final room = PanelTypesEnum.room.def;
      expect(activity.minWidth, room.minWidth);
      expect(activity.reasonableMin, room.reasonableMin);
      expect(activity.idealWidth, room.idealWidth);
    });
  });

  group('the fold is positional, not registry-linked (#9030)', () {
    // routing.instructions.md: "When a column's two panels are not a registry
    // master/detail pair (a course card with a live room beside it), the same
    // rule applies positionally — the first token folds behind the second."
    // `course` has no parent and `room`'s parent is `chats`, so before #9030
    // this pair could not fold at all: both held a full slot, the left column
    // ate the budget, and Tier 2 evicted the analytics panel instead.
    test('a chat opened in a course folds the course card behind it', () {
      // 1100px: the pair's comfort widths (480 + 480 + a 16 gap) no longer fit
      // the budget, which is the fold trigger.
      final l = run(
        viewport: 1100,
        left: [PanelTypesEnum.course, PanelTypesEnum.room],
      );
      expect(l.left[0].vis, PanelVis.hidden); // course folds
      expect(l.left[1].vis, PanelVis.full); // the live room keeps the column
      // Closing the room reveals the card as it was left, so its control is ←.
      expect(l.left[1].foldedOver, isTrue);
      expectNoOverlap(l);
    });

    test('the folded course leaves room for the analytics panel — the '
        'reported bug', () {
      // The repro state of #9030: a course, an activity chat opened from its
      // chats section, and an analytics page. The analytics panel must draw
      // whichever left panel the user touched most recently, so pressing an
      // analytics button is never a no-op.
      for (final focusHint in [0, 1, 2]) {
        final l = run(
          viewport: 1200,
          left: [PanelTypesEnum.course, PanelTypesEnum.room],
          right: [PanelTypesEnum.analytics],
          focusHint: focusHint,
        );
        expect(
          l.right.single.vis,
          PanelVis.full,
          reason: 'analytics must draw with focusHint=$focusHint',
        );
        expect(l.left[1].vis, PanelVis.full); // the room keeps the column
        expectNoOverlap(l);
      }
    });

    test('nothing folds while both panels still fit their comfort width', () {
      // The fold is a response to width pressure, never a default (#7467).
      final l = run(
        viewport: 1700,
        left: [PanelTypesEnum.course, PanelTypesEnum.room],
      );
      expect(l.left.every((s) => s.vis == PanelVis.full), isTrue);
      expect(l.left.every((s) => !s.foldedOver), isTrue);
      expectNoOverlap(l);
    });
  });

  group('registry-declared always-fold (stacksOnParent, #7826)', () {
    test(
      'the add-course hub folds behind its subpage even on a wide viewport',
      () {
        final l = run(
          left: [PanelTypesEnum.addcourse, PanelTypesEnum.addcoursepage],
        );
        // 1600px fits both comfortably — the fold is by declaration, not width.
        expect(l.left[0].vis, PanelVis.hidden);
        expect(l.left[1].vis, PanelVis.full);
        // The subpage closes back to the folded hub, so its control reads ←.
        expect(l.left[1].foldedOver, isTrue);
        // The width the hub would have claimed stays with the map.
        expect(l.mapLeftOverlay, 73 + l.left[1].width);
        expectNoOverlap(l);
      },
    );

    test('the hub alone (no subpage open) still draws', () {
      final l = run(left: [PanelTypesEnum.addcourse]);
      expect(l.left.single.vis, PanelVis.full);
      expect(l.left.single.foldedOver, isFalse);
    });

    // #8972: the hub is an index of course tiles, so it draws at the chat
    // list's width — switching rail sections between them must not resize the
    // column — and its subpages share that width, so entering the add-course
    // flow doesn't resize it either.
    test('the hub and its subpages are list-width, like the chat list', () {
      final chats = PanelTypesEnum.chats.def;
      for (final type in [
        PanelTypesEnum.addcourse,
        PanelTypesEnum.addcoursepage,
      ]) {
        expect(type.def.minWidth, chats.minWidth, reason: '$type min');
        expect(
          type.def.reasonableMin,
          chats.reasonableMin,
          reason: '$type comfort',
        );
        expect(type.def.idealWidth, chats.idealWidth, reason: '$type ideal');
      }
      final chatsWidth = run(left: [PanelTypesEnum.chats]).left.single.width;
      expect(
        run(left: [PanelTypesEnum.addcourse]).left.single.width,
        chatsWidth,
      );
      // The subpage always folds the hub, so it is the column's only panel.
      final flow = run(
        left: [PanelTypesEnum.addcourse, PanelTypesEnum.addcoursepage],
      );
      expect(flow.left[1].width, chatsWidth);
    });

    // The chips on a course tile fit one line at the list ideal: a tile spends
    // 124 on card margin, list padding, the 48px avatar and its gap, and the
    // widest chip row (Intermediate Mid (B1), three-digit counts) needs 316.
    test('the list ideal leaves a course tile room for unwrapped chips', () {
      expect(PanelWidths.listIdeal - 124, greaterThanOrEqualTo(316.0));
    });

    test('only the add-course subpage declares the always-fold', () {
      for (final type in PanelTypesEnum.values) {
        expect(
          type.def.stacksOnParent,
          type == PanelTypesEnum.addcoursepage,
          reason: '$type stacksOnParent',
        );
      }
    });
  });

  // #9037 — the course seats LAST now, so the positional rule alone would fold
  // the CHAT behind the course card. That would strand it: a panel with a floor
  // shows only its chevron ([CloseAffordance]), so it can offer neither an X nor
  // a back arrow to reveal whatever folded behind it.
  group('a floor panel is the one that yields, whatever its position', () {
    test('a chat seated before the course folds the COURSE, not the chat', () {
      final l = run(
        viewport: 1100,
        left: [PanelTypesEnum.room, PanelTypesEnum.course],
      );
      expect(l.left[1].vis, PanelVis.hidden); // the course yields
      expect(l.left[0].vis, PanelVis.full); // the live chat keeps the column
      // Nothing folded BENEATH the chat, so its control stays an X — which
      // reveals the course card just the same, by dropping the chat.
      expect(l.left[0].foldedOver, isFalse);
      expectNoOverlap(l);
    });

    test('and it still yields when seated first (#9030 is unchanged)', () {
      final l = run(
        viewport: 1100,
        left: [PanelTypesEnum.course, PanelTypesEnum.room],
      );
      expect(l.left[0].vis, PanelVis.hidden);
      expect(l.left[1].vis, PanelVis.full);
      expect(l.left[1].foldedOver, isTrue); // folded beneath → back arrow
      expectNoOverlap(l);
    });

    test('a pair with no floor still folds purely by position', () {
      final l = run(
        viewport: 1100,
        left: [PanelTypesEnum.chats, PanelTypesEnum.room],
      );
      expect(l.left[0].width + l.left[1].width, greaterThan(0));
      final tight = run(
        viewport: 900,
        left: [PanelTypesEnum.chats, PanelTypesEnum.room],
      );
      expect(tight.left[0].vis, PanelVis.hidden); // the list, beneath, folds
      expect(tight.left[1].vis, PanelVis.full);
      expect(tight.left[1].foldedOver, isTrue);
    });

    test('exactly one panel type declares a floor', () {
      final withFloor = PanelTypesEnum.values
          .where((t) => t.hasCavityFloor)
          .toList();
      expect(withFloor, [PanelTypesEnum.course]);
    });
  });
}

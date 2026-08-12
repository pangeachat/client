import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map_ranking.dart';

void main() {
  // The real large-card footprint. The card sits ABOVE its pin (flutter_map's
  // Alignment.topCenter): the point is the card's bottom-center, so a card at
  // (x, y) occupies x[x-130, x+130], y[y-184, y]. Baseline y=300 clears the top.
  const card = Size(260, 184);
  // An 800x600 map viewport with nothing docked over it.
  const viewport = Rect.fromLTWH(0, 0, 800, 600);

  PlacementResult place({
    required Map<String, Offset?> offsets,
    List<String>? ordered,
    String? focusedId,
    Rect safeArea = viewport,
    int largeBudget = 3,
    Set<String> dismissedIds = const {},
    // Defaults to "everyone eligible" so the fit/overlap/focus/dismissal tests
    // below (which aren't testing state gating) are unaffected by the
    // large-tier hard gate; tests of the gate itself pass a narrower set.
    Set<String>? largeEligibleIds,
  }) => placeLargeCards(
    orderedCandidates: ordered ?? offsets.keys.toList(),
    focusedId: focusedId,
    screenOffsetOf: (id) => offsets[id],
    cardSize: card,
    safeArea: safeArea,
    largeBudget: largeBudget,
    dismissedIds: dismissedIds,
    largeEligibleIds: largeEligibleIds ?? offsets.keys.toSet(),
  );

  // The mid teardrop footprint: head 44 wide, point 10 tall, anchored tip at
  // the offset, box extending UP — a pin at (x, y) occupies x[x-22, x+22],
  // y[y-54, y]. Heads 44px wide, so centres <44px apart horizontally overlap.
  MidPlacementResult placeMid({
    required Map<String, Offset?> offsets,
    List<String>? ordered,
    String? focusedId,
    int midBudget = 10,
    List<Rect> obstacleRects = const [],
  }) => placeMidPins(
    orderedCandidates: ordered ?? offsets.keys.toList(),
    focusedId: focusedId,
    screenOffsetOf: (id) => offsets[id],
    midBudget: midBudget,
    obstacleRects: obstacleRects,
  );

  group('placeLargeCards — fit and overlap', () {
    test('well-separated candidates both fit', () {
      final r = place(
        offsets: {'a': const Offset(200, 300), 'b': const Offset(600, 300)},
      );
      expect(r.largeIds, ['a', 'b']);
    });

    test('overlapping cards: the lower-scored yields its large slot', () {
      // a spans x[70,330]; b spans x[190,450] — they overlap.
      final r = place(
        offsets: {'a': const Offset(200, 300), 'b': const Offset(320, 300)},
      );
      expect(r.largeIds, ['a']);
    });

    test('emergent count: a crammed view drops below the budget', () {
      // a and b overlap; c is clear. Budget 3, but only a + c fit.
      final r = place(
        offsets: {
          'a': const Offset(200, 300),
          'b': const Offset(320, 300),
          'c': const Offset(600, 300),
        },
      );
      expect(r.largeIds, ['a', 'c']);
    });

    test('a card with no room at the right edge yields to its dot', () {
      // x[570,830] spills past the 800 right edge.
      final r = place(offsets: {'a': const Offset(700, 300)});
      expect(r.largeIds, isEmpty);
    });

    test('a card with no room at the top edge yields', () {
      // The card balloons up: y[-84,100] spills above the 0 top edge.
      final r = place(offsets: {'a': const Offset(200, 100)});
      expect(r.largeIds, isEmpty);
    });

    test('a pin near the bottom edge fits (its card extends up into view)', () {
      // y[396,580] — well inside the 600-tall viewport.
      final r = place(offsets: {'a': const Offset(200, 580)});
      expect(r.largeIds, ['a']);
    });

    test('a card under an open panel (inset safe area) yields', () {
      // A 300px-wide left panel; a's footprint x[190,450] crosses into it.
      final r = place(
        offsets: {'a': const Offset(320, 300)},
        safeArea: const Rect.fromLTRB(300, 0, 800, 600),
      );
      expect(r.largeIds, isEmpty);
    });

    test('an unprojectable candidate is skipped', () {
      final r = place(offsets: {'a': null, 'b': const Offset(600, 300)});
      expect(r.largeIds, ['b']);
    });

    test('a zero large budget places nothing', () {
      final r = place(
        offsets: {'a': const Offset(200, 300), 'b': const Offset(600, 300)},
        largeBudget: 0,
      );
      expect(r.largeIds, isEmpty);
    });
  });

  group('placeLargeCards — focused priority', () {
    test('a focused candidate is placed first; featured yields around it', () {
      // s spans x[70,330]; f overlaps it (x[170,430]); g is clear (x[470,730]).
      // Even though f outranks s in the ordered list, s (focused) claims its
      // footprint first, so f yields and g still fits.
      final r = place(
        offsets: {
          's': const Offset(200, 300),
          'f': const Offset(300, 300),
          'g': const Offset(600, 300),
        },
        ordered: ['f', 's', 'g'],
        focusedId: 's',
      );
      expect(r.largeIds, contains('s'));
      expect(r.largeIds, contains('g'));
      expect(r.largeIds, isNot(contains('f')));
    });

    test('a focused pin that is not a candidate is not forced large', () {
      // s projects on-screen but isn't in the ranked candidates this view, so it
      // stays a dot (with its focus ring) — focus does not force a card.
      final r = place(
        offsets: {'s': const Offset(200, 300), 'a': const Offset(600, 300)},
        ordered: ['a'],
        focusedId: 's',
      );
      expect(r.largeIds, ['a']);
    });

    test('a focused card that does not fit yields to its dot', () {
      // x[650,910] spills past the 800 right edge — focus no longer overrides
      // the fit test (there is no peek to keep on screen).
      final r = place(
        offsets: {'s': const Offset(780, 300)},
        ordered: ['s'],
        focusedId: 's',
      );
      expect(r.largeIds, isEmpty);
    });
  });

  group('placeLargeCards — X-dismissals (#7207)', () {
    test('a dismissed candidate never places large; the next back-fills', () {
      // a and b overlap, so with a dismissed, b takes the slot a blocked.
      final r = place(
        offsets: {'a': const Offset(200, 300), 'b': const Offset(320, 300)},
        dismissedIds: {'a'},
      );
      expect(r.largeIds, ['b']);
    });

    test('a dismissed focused pin is not placed despite focused-first', () {
      // Dismissing a focused card also clears focus in the controller, but the
      // placement itself must hold the demotion even if focus lingers a frame.
      final r = place(
        offsets: {'s': const Offset(200, 300), 'a': const Offset(600, 300)},
        ordered: ['s', 'a'],
        focusedId: 's',
        dismissedIds: {'s'},
      );
      expect(r.largeIds, ['a']);
    });

    test('dismissing every candidate places nothing (all demote to dots)', () {
      final r = place(
        offsets: {'a': const Offset(200, 300), 'b': const Offset(600, 300)},
        dismissedIds: {'a', 'b'},
      );
      expect(r.largeIds, isEmpty);
    });
  });

  group(
    'placeLargeCards — respects the large-eligible set (completed excluded)',
    () {
      test('a non-eligible id is never placed large, however well it fits', () {
        // 'a' fits fine geometrically and is even first in ranked order, but it's
        // not in largeEligibleIds (e.g. a completed trail-star pin, the one state
        // the view leaves out) — it must never place large. 'b' is eligible and
        // back-fills the slot.
        final r = place(
          offsets: {'a': const Offset(200, 300), 'b': const Offset(600, 300)},
          largeEligibleIds: {'b'},
        );
        expect(r.largeIds, ['b']);
      });

      test('an empty eligible set places nothing regardless of fit/budget', () {
        final r = place(
          offsets: {'a': const Offset(200, 300), 'b': const Offset(600, 300)},
          largeBudget: 5,
          largeEligibleIds: const {},
        );
        expect(r.largeIds, isEmpty);
      });

      test(
        'a non-eligible focused pin is not placed despite focused-first',
        () {
          final r = place(
            offsets: {'s': const Offset(200, 300), 'a': const Offset(600, 300)},
            ordered: ['s', 'a'],
            focusedId: 's',
            largeEligibleIds: {'a'},
          );
          expect(r.largeIds, ['a']);
        },
      );
    },
  );

  group('placeMidPins — overlap demotion', () {
    // A large card's footprint at pin point (x, y): x[x-130, x+130], y[y-184, y].
    Rect cardAt(Offset o) => Rect.fromLTWH(o.dx - 130, o.dy - 184, 260, 184);

    test('well-separated mid pins all place', () {
      final r = placeMid(
        offsets: {'a': const Offset(100, 300), 'b': const Offset(300, 300)},
      );
      expect(r.midIds, {'a', 'b'});
    });

    test('two overlapping mids: the higher-scored wins, the other demotes', () {
      // 20px apart horizontally → the 44px heads overlap.
      final r = placeMid(
        offsets: {'hi': const Offset(100, 300), 'lo': const Offset(120, 300)},
        ordered: ['hi', 'lo'], // 'hi' ranks first
      );
      expect(r.midIds, {'hi'});
    });

    test('a mid pin under a placed large card is demoted', () {
      final r = placeMid(
        offsets: {'under': const Offset(200, 300)},
        obstacleRects: [cardAt(const Offset(200, 300))],
      );
      expect(r.midIds, isEmpty);
    });

    test('a mid pin clear of the card keeps its tier', () {
      final r = placeMid(
        offsets: {'clear': const Offset(600, 300)},
        obstacleRects: [cardAt(const Offset(200, 300))],
      );
      expect(r.midIds, {'clear'});
    });

    test('a focused mid is placed first and keeps its spot over a '
        'higher-scored overlapping peer', () {
      final r = placeMid(
        offsets: {'hi': const Offset(100, 300), 'f': const Offset(115, 300)},
        ordered: ['hi', 'f'], // 'hi' scores higher, but 'f' is focused
        focusedId: 'f',
      );
      expect(r.midIds, {'f'});
    });

    test('the mid budget bounds the placed count', () {
      final r = placeMid(
        offsets: {
          'a': const Offset(100, 300),
          'b': const Offset(300, 300),
          'c': const Offset(500, 300),
        },
        midBudget: 2,
      );
      expect(r.midIds.length, 2);
    });

    test('a candidate off the projection is skipped, not blocking others', () {
      final r = placeMid(
        offsets: {'gone': null, 'here': const Offset(300, 300)},
      );
      expect(r.midIds, {'here'});
    });
  });
}

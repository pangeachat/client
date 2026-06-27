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
    String? selectedId,
    Iterable<String>? visibleIds,
    Rect safeArea = viewport,
    int largeBudget = 3,
  }) => placeLargeCards(
    orderedCandidates: ordered ?? offsets.keys.toList(),
    selectedId: selectedId,
    visibleIds: visibleIds ?? offsets.keys,
    screenOffsetOf: (id) => offsets[id],
    cardSize: card,
    safeArea: safeArea,
    largeBudget: largeBudget,
  );

  group('placeLargeCards — fit and overlap', () {
    test('well-separated candidates both fit', () {
      final r = place(
        offsets: {'a': const Offset(200, 300), 'b': const Offset(600, 300)},
      );
      expect(r.largeIds, ['a', 'b']);
      expect(r.suppressedIds, isEmpty);
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
  });

  group('placeLargeCards — selected priority', () {
    test('selected is always large and featured yields around it', () {
      // s spans x[70,330]; f overlaps it (x[170,430]); g is clear (x[470,730]).
      final r = place(
        offsets: {
          's': const Offset(200, 300),
          'f': const Offset(300, 300),
          'g': const Offset(600, 300),
        },
        ordered: ['f', 'g'],
        selectedId: 's',
      );
      expect(r.largeIds, contains('s'));
      expect(r.largeIds, contains('g'));
      expect(r.largeIds, isNot(contains('f')));
    });

    test('selected never yields even spilling an edge', () {
      final r = place(
        offsets: {'s': const Offset(780, 300)}, // x[650,910] off the right edge
        ordered: const [],
        selectedId: 's',
      );
      expect(r.largeIds, ['s']);
    });

    test('an unprojectable selection claims no large slot', () {
      // s has no screen point (fell out of view); three featured cards all fit
      // (centers 130/390/650 → touching, non-overlapping). A stale selection
      // must not silently burn a slot and drop the third featured to its dot.
      final r = place(
        offsets: {
          's': null,
          'a': const Offset(130, 300),
          'b': const Offset(390, 300),
          'c': const Offset(650, 300),
        },
        ordered: ['a', 'b', 'c'],
        selectedId: 's',
      );
      expect(r.largeIds, ['a', 'b', 'c']);
    });
  });

  group('placeLargeCards — cluster suppression', () {
    test('long-tail pins under a placed card are suppressed', () {
      final r = place(
        offsets: {
          'a': const Offset(400, 300), // placed: rect x[270,530], y[116,300]
          'under': const Offset(400, 200), // inside the card
          'outside': const Offset(400, 500), // below the pin, outside the card
        },
        ordered: ['a'],
      );
      expect(r.largeIds, ['a']);
      expect(r.suppressedIds, contains('under'));
      expect(r.suppressedIds, isNot(contains('outside')));
    });

    test('a selected card also suppresses the long tail beneath it', () {
      final r = place(
        offsets: {'s': const Offset(400, 300), 'under': const Offset(400, 200)},
        ordered: const [],
        selectedId: 's',
        visibleIds: ['s', 'under'],
      );
      expect(r.suppressedIds, contains('under'));
    });
  });
}

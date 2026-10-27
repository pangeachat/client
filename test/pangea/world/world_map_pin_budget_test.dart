import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map_pin_budget.dart';

/// The width-driven pin budget (world-map.instructions.md, "Pin display"): the
/// visible map width caps how many pins and cards show, and as it narrows the
/// cards go first, then the mid pins, until only dots are left. The counts are
/// tuning, so these pin the shape of the table rather than its numbers.
void main() {
  const bands = kPinBudgetBreakpoints;

  group('the breakpoint table', () {
    test('runs widest first and its last band covers zero width', () {
      for (var i = 1; i < bands.length; i++) {
        expect(bands[i].minWidth, lessThan(bands[i - 1].minWidth));
      }
      expect(bands.last.minWidth, 0);
    });

    test('as the width narrows, no tier grows', () {
      for (var i = 1; i < bands.length; i++) {
        final wider = bands[i - 1].budget;
        final narrower = bands[i].budget;
        expect(narrower.large, lessThanOrEqualTo(wider.large));
        expect(narrower.mid, lessThanOrEqualTo(wider.mid));
        expect(narrower.total, lessThanOrEqualTo(wider.total));
      }
    });

    test('cards are gone wherever mid pins are', () {
      for (final band in bands) {
        if (band.budget.mid == 0) expect(band.budget.large, 0);
      }
    });

    test('the widest band shows cards and the narrowest only dots', () {
      expect(bands.first.budget.large, greaterThan(0));
      expect(bands.last.budget.large, 0);
      expect(bands.last.budget.mid, 0);
      expect(bands.last.budget.small, greaterThan(0));
    });

    test('each band reserves its trail inside its total', () {
      for (final band in bands) {
        expect(band.budget.trail, lessThanOrEqualTo(band.budget.total));
      }
    });
  });

  group('budgetForWidth', () {
    test('a width takes the first band it meets, stepped', () {
      for (var i = 0; i < bands.length; i++) {
        expect(budgetForWidth(bands[i].minWidth), same(bands[i].budget));
        if (i > 0) {
          expect(
            budgetForWidth(bands[i - 1].minWidth - 1),
            same(bands[i].budget),
          );
        }
      }
    });
  });
}

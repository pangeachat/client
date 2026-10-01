import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/close_affordance.dart';

void main() {
  CloseAffordance of({
    bool pushed = false,
    bool reveals = false,
    bool floor = false,
  }) => CloseAffordance.of(
    isPushedPage: pushed,
    revealsMaster: reveals,
    hasFloor: floor,
  );

  group('CloseAffordance', () {
    test('a root / coexisting panel shows X only', () {
      final a = of();
      expect(a.showClose, isTrue);
      expect(a.showBack, isFalse);
    });

    test(
      'a folded detail (reveals its master) shows back only — X redundant',
      () {
        final a = of(reveals: true);
        expect(a.showBack, isTrue);
        expect(a.showClose, isFalse);
      },
    );

    test(
      'a pushed page / wizard step shows BOTH (← pops a level, X dismisses)',
      () {
        final a = of(pushed: true);
        expect(a.showBack, isTrue);
        expect(a.showClose, isTrue);
      },
    );

    test('pushed AND folded still shows both (push dominates)', () {
      final a = of(pushed: true, reveals: true);
      expect(a.showBack, isTrue);
      expect(a.showClose, isTrue);
    });

    test('a floor panel shows the chevron ONLY — nothing to close to '
        '(#8816)', () {
      final a = of(floor: true);
      expect(a.showChevron, isTrue);
      expect(a.showBack, isFalse);
      expect(a.showClose, isFalse);
    });

    test('the floor dominates: a pushed or folded floor panel is still just '
        'the chevron', () {
      // The narrow course cavity never leaves the screen, so neither an X nor
      // a back arrow has a destination no matter how it was reached.
      for (final a in [
        of(floor: true, pushed: true),
        of(floor: true, reveals: true),
        of(floor: true, pushed: true, reveals: true),
      ]) {
        expect(a.showChevron, isTrue);
        expect(a.showBack, isFalse);
        expect(a.showClose, isFalse);
      }
    });

    test('every other panel shows no chevron', () {
      for (final a in [of(), of(pushed: true), of(reveals: true)]) {
        expect(a.showChevron, isFalse);
      }
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/close_affordance.dart';

void main() {
  CloseAffordance of({bool pushed = false, bool reveals = false}) =>
      CloseAffordance.of(isPushedPage: pushed, revealsMaster: reveals);

  group('CloseAffordance', () {
    test('a root / coexisting panel shows X only', () {
      final a = of();
      expect(a.showClose, isTrue);
      expect(a.showBack, isFalse);
    });

    test('a folded detail (reveals its master) shows back only — X redundant', () {
      final a = of(reveals: true);
      expect(a.showBack, isTrue);
      expect(a.showClose, isFalse);
    });

    test('a pushed page / wizard step shows BOTH (← pops a level, X dismisses)', () {
      final a = of(pushed: true);
      expect(a.showBack, isTrue);
      expect(a.showClose, isTrue);
    });

    test('pushed AND folded still shows both (push dominates)', () {
      final a = of(pushed: true, reveals: true);
      expect(a.showBack, isTrue);
      expect(a.showClose, isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/utils/single_flight_guard.dart';

// The pure re-entry guard used by the checkout / cancel / portal tap handlers:
// a double-tap must never fire concurrent checkouts, cancels, or redirects.
void main() {
  group('SingleFlightGuard', () {
    test('starts idle', () {
      expect(SingleFlightGuard().inFlight, isFalse);
    });

    test('tryEnter locks; a second tryEnter is refused while in flight', () {
      final guard = SingleFlightGuard();
      expect(guard.tryEnter(), isTrue);
      expect(guard.inFlight, isTrue);
      expect(guard.tryEnter(), isFalse); // the double-tap path
      expect(guard.inFlight, isTrue);
    });

    test('exit unlocks; the next tryEnter succeeds', () {
      final guard = SingleFlightGuard();
      expect(guard.tryEnter(), isTrue);
      guard.exit();
      expect(guard.inFlight, isFalse);
      expect(guard.tryEnter(), isTrue);
    });

    test('exit is idempotent', () {
      final guard = SingleFlightGuard();
      guard.exit();
      guard.exit();
      expect(guard.inFlight, isFalse);
      expect(guard.tryEnter(), isTrue);
    });
  });
}

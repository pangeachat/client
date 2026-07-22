import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/authentication/p_logout.dart';

/// The logout flow must FLUSH + dispose the account's dosage/analytics BEFORE
/// `client.logout()` invalidates the bearer — otherwise the final engagement
/// span POSTs with a dead token. [saveFlushAndLogout] is the ordering the real
/// logout path uses.
void main() {
  test('flushes + disposes before logging out (bearer still valid)', () async {
    final order = <String>[];
    await saveFlushAndLogout(
      saveAnalytics: () async => order.add('save'),
      flushAndDispose: () async => order.add('flush'),
      logout: () async {
        // By the time logout runs, the flush must already be done.
        expect(
          order,
          contains('flush'),
          reason:
              'the dosage flush must complete BEFORE logout invalidates '
              'the bearer',
        );
        order.add('logout');
      },
    );
    expect(order, ['save', 'flush', 'logout']);
  });
}

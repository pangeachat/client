import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/authentication/p_logout.dart';

/// The logout flow must FLUSH the account's final dosage span BEFORE
/// `client.logout()` invalidates the bearer — otherwise the span POSTs with a
/// dead token. The flush is also best-effort: it must NEVER block or fail the
/// logout. [saveFlushAndLogout] is the ordering the real logout path uses.
void main() {
  test('flushes before logging out (bearer still valid)', () async {
    final order = <String>[];
    await saveFlushAndLogout(
      saveAnalytics: () async => order.add('save'),
      flushTelemetry: () async => order.add('flush'),
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

  test(
    'a failing save still logs out (telemetry never blocks logout)',
    () async {
      var loggedOut = false;
      await saveFlushAndLogout(
        saveAnalytics: () async => throw Exception('save boom'),
        flushTelemetry: () async {},
        logout: () async => loggedOut = true,
      );
      expect(
        loggedOut,
        isTrue,
        reason: 'a save failure must be swallowed and logout must still run',
      );
    },
  );

  test(
    'a failing flush still logs out (telemetry never blocks logout)',
    () async {
      var loggedOut = false;
      await saveFlushAndLogout(
        saveAnalytics: () async {},
        flushTelemetry: () async => throw Exception('flush boom'),
        logout: () async => loggedOut = true,
      );
      expect(
        loggedOut,
        isTrue,
        reason: 'a flush failure must be swallowed and logout must still run',
      );
    },
  );
}

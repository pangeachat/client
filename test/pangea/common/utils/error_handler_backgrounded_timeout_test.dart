import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// #9132: a request timeout while the app is not resumed describes the
/// device's sleep, not the network — iOS suspends the socket and every
/// pending timer fires together on wake — so the severity table's Timeout row
/// says it is not reported at all. Pinned at the reporting sink, where the
/// unsubscribed-user rule already lives, so every timeout site is covered.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  TimeoutException timeout() => TimeoutException(
    'GET /choreo/v2/activity/{id}',
    const Duration(seconds: 10),
  );

  group('ErrorHandler.shouldReport for a TimeoutException', () {
    tearDown(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );

    test('is reported while the app is resumed', () {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(ErrorHandler.shouldReport(timeout()), isTrue);
    });

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      test('is not reported while the app is $state', () {
        binding.handleAppLifecycleStateChanged(state);
        expect(ErrorHandler.shouldReport(timeout()), isFalse);
      });
    }

    test('any other failure is still reported while backgrounded', () {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(
        ErrorHandler.shouldReport(Exception('choreo unreachable')),
        isTrue,
      );
    });
  });
}

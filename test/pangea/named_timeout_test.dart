import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/utils/named_timeout.dart';

/// #8889: a bare `timeout()` throws a message-less [TimeoutException] whose
/// web stack is only the timer callback, so every expired wait collapsed into
/// one Sentry issue with nothing to act on (CLIENT-AXX). The name is what the
/// fingerprint groups on, so it has to survive the throw intact.
void main() {
  group('timeoutNamed', () {
    test('an expired wait throws a TimeoutException naming the operation', () {
      final never = Completer<void>().future;
      expect(
        never.timeoutNamed(
          const Duration(milliseconds: 1),
          'waitForRoomInSync: create room',
        ),
        throwsA(
          isA<TimeoutException>()
              .having(
                (e) => e.message,
                'message',
                'waitForRoomInSync: create room',
              )
              .having(
                (e) => e.duration,
                'duration',
                const Duration(milliseconds: 1),
              ),
        ),
      );
    });

    test('a wait that completes in time passes its value through', () async {
      expect(
        await Future.value(42).timeoutNamed(const Duration(seconds: 1), 'op'),
        42,
      );
    });
  });
}

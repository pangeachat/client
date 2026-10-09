import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/chat.dart';

/// [ChatController.scrollUpBannerEventIdAfterLoadError] decides what the
/// timeline load's network-error fallback shows. A plain open has no event
/// context, and asserting one threw past the fallback into the "Oops,
/// something went wrong" snackbar on a chat that had loaded (CLIENT-CYX).
void main() {
  const eventId = r'$jump:fakeServer.notExisting';

  test('plain open with a network error offers no banner', () {
    expect(
      ChatController.scrollUpBannerEventIdAfterLoadError(
        TimeoutException('history'),
        null,
      ),
      isNull,
    );
    expect(
      ChatController.scrollUpBannerEventIdAfterLoadError(
        const SocketException('Failed host lookup'),
        null,
      ),
      isNull,
    );
  });

  test('jump with a network error offers the event it was opening on', () {
    expect(
      ChatController.scrollUpBannerEventIdAfterLoadError(
        TimeoutException('context'),
        eventId,
      ),
      eventId,
    );
    expect(
      ChatController.scrollUpBannerEventIdAfterLoadError(
        const SocketException('Failed host lookup'),
        eventId,
      ),
      eventId,
    );
  });

  test('a non-network error offers no banner', () {
    expect(
      ChatController.scrollUpBannerEventIdAfterLoadError(
        StateError('bad timeline'),
        eventId,
      ),
      isNull,
    );
  });
}

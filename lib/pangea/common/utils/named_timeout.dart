import 'dart:async';

/// [Future.timeout] whose failure names the operation it bounded.
///
/// A bare `timeout()` throws a message-less [TimeoutException], and on the web
/// its stack is only the timer callback — no app frame at all — so every
/// expired wait in the app (a sync wait after creating a room, a profile save,
/// a repo fetch), with 5s, 10s and 15s bounds mixed together, collapsed into
/// one Sentry issue that said nothing (CLIENT-AXX, #8889). The name is the
/// grouping key (`PangeaHttpException.fingerprintOf`), so keep it stable and
/// free of ids: method + normalized path for an HTTP read, the awaited call +
/// surface for a sync wait.
extension NamedTimeout<T> on Future<T> {
  Future<T> timeoutNamed(Duration limit, String operation) =>
      timeout(limit, onTimeout: () => throw TimeoutException(operation, limit));
}

/// A minimal, synchronous re-entry guard for tap handlers that must never run
/// twice concurrently — a double-tap on the checkout / cancel / manage-billing
/// controls must not fire concurrent requests or multiple redirects.
///
/// Usage:
/// ```dart
/// if (!_guard.tryEnter()) return;   // a run is already in flight
/// try { ...await work... } finally { _guard.exit(); }
/// ```
class SingleFlightGuard {
  bool _inFlight = false;

  /// Whether a run is currently in flight (drives disabled/loading UI).
  bool get inFlight => _inFlight;

  /// Locks and returns true when idle; returns false when a run is already in
  /// flight (the caller must early-return).
  bool tryEnter() {
    if (_inFlight) return false;
    _inFlight = true;
    return true;
  }

  /// Unlocks. Safe to call when already idle (idempotent); call from `finally`.
  void exit() => _inFlight = false;
}

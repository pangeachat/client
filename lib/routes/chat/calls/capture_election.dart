/// Decides whether this device is the one that records a call.
///
/// A learner signed in on two devices would otherwise have both record their own
/// microphone, and be credited twice for saying something once.
///
/// The decision is local and needs no agreement. Every device ranks the same
/// device ids the same way and reaches the same verdict without exchanging a
/// message, so there is nothing to negotiate, nothing to confirm, and nothing
/// that can deadlock or flap.
///
/// It is deliberately blunt: device ids carry no meaning, so the winner may be
/// the device the learner has walked away from. That costs a stretch of credit
/// until the other device leaves the call. Losing credit is recoverable and
/// inventing it is not, which is the trade this makes.
class CaptureElection {
  /// This device.
  final String myDeviceId;

  /// The learner's other devices holding a live membership in the same call, as
  /// far as this device can see. May include this device; may be stale; may be
  /// empty because nothing else is there or because nothing else is visible yet.
  final Iterable<String> siblingDeviceIds;

  const CaptureElection({
    required this.myDeviceId,
    required this.siblingDeviceIds,
  });

  /// Whether this device records.
  ///
  /// True when no sibling sorts before it. This device is always part of its own
  /// comparison, so a device that cannot see its own membership — a write that
  /// was lost, a sync that has not caught up — still ranks itself rather than
  /// concluding it is absent and falling silent.
  ///
  /// Seeing more devices can turn this false. Seeing fewer never can.
  bool get shouldRecord =>
      !siblingDeviceIds.any((id) => id.compareTo(myDeviceId) < 0);
}

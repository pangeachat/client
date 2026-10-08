import 'dart:math' as math;

import 'package:fluffychat/routes/chat/calls/call_notification.dart';

/// Whether a device that is leaving a call was the call's PREDECESSOR -- the
/// learner moved the call from it to another of their devices -- rather than
/// one of two devices that answered the same ring (client#9173).
///
/// The difference decides what happens to what it captured. A device that lost
/// an ANSWER RACE captured the same opening seconds its sibling did, so it
/// publishes nothing and the stretch is credited once. A predecessor captured
/// a stretch of the conversation nobody else has -- everything said before the
/// learner picked up their other device -- so it publishes its half, its audio
/// and its credit, exactly as if it had carried on.
///
/// Decided on the SFU's clock, the one clock both devices observe:
///
/// * it had a talk segment (the other person was there) BEFORE it first saw
///   the sibling, and
/// * the sibling's SFU join -- latched the first time this device saw it, and
///   never moved by a later rejoin -- is later than the ring could have been
///   sent plus the ring's whole lifetime plus margins. Inside that window the
///   sibling may simply have answered the same ring a little later, which is
///   a race, and a race publishes nothing (owner decision 2).
///
/// No anchor, or no bound on the ring, means NOT a predecessor: losing a
/// stretch of credit is recoverable, inventing a duplicate of it is not.
abstract final class CallPredecessor {
  /// The longest a ring can live: any sibling joining within it may have
  /// answered it.
  static const ringLifetime = CallNotification.maxLifetime;

  /// Clock skew between the ring's stamp and the SFU, the time a learner may
  /// take to answer after the ring ends, and the whole-second resolution of a
  /// join stamp that did not carry milliseconds.
  static const margin = Duration(seconds: 15 + 15 + 2);

  /// The latest the call's ring can have been sent, on the SFU's clock, or null
  /// when this device cannot bound it.
  ///
  /// [anchorSfuMs] is this device's own SFU join. The two monotonic readings
  /// are measured from a point taken BEFORE this device began connecting, so
  /// adding them to its join overstates the instant they describe -- an upper
  /// bound, which is the safe direction: a later bound only ever turns a
  /// predecessor into a race.
  ///
  /// * Rung or joining a call already under way: the ring went out before this
  ///   device joined, so its own join bounds it.
  /// * Placed it: the ring went out no later than the moment `ring` returned.
  /// * Glare: their ring reached this device no later than it arrived.
  /// * A rejoined device knows neither, so it has no bound.
  static int? ringUpperSfuMs({
    required int? anchorSfuMs,
    required bool placed,
    required bool peerAlsoPlaced,
    required bool rejoined,
    required int? ringReturnedAfterConnectStartMs,
    required int? peerRingArrivedAfterConnectStartMs,
  }) {
    if (anchorSfuMs == null || rejoined) return null;
    final bounds = <int>[];
    if (placed) {
      if (ringReturnedAfterConnectStartMs == null) return null;
      bounds.add(anchorSfuMs + ringReturnedAfterConnectStartMs);
    }
    if (peerAlsoPlaced) {
      if (peerRingArrivedAfterConnectStartMs == null) return null;
      bounds.add(anchorSfuMs + peerRingArrivedAfterConnectStartMs);
    }
    if (!placed && !peerAlsoPlaced) bounds.add(anchorSfuMs);
    return bounds.reduce(math.max);
  }

  /// The rule itself. [siblingFirstJoinSfuMs] is every sibling's latched first
  /// join; the EARLIEST decides, so a predecessor is never claimed on the
  /// strength of one late sibling while another joined inside the window.
  static bool isPredecessor({
    required bool talkedBeforeFirstSibling,
    required Iterable<int> siblingFirstJoinSfuMs,
    required int? ringUpperSfuMs,
  }) {
    if (!talkedBeforeFirstSibling || ringUpperSfuMs == null) return false;
    if (siblingFirstJoinSfuMs.isEmpty) return false;
    final earliest = siblingFirstJoinSfuMs.reduce(math.min);
    return earliest - ringUpperSfuMs > (ringLifetime + margin).inMilliseconds;
  }
}

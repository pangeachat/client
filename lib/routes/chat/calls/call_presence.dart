import 'package:flutter/foundation.dart';

/// Tracks which calls this client believes are live.
///
/// Split out of the delegate because the two rules it encodes are easy to get wrong,
/// invisible when wrong, and otherwise only reachable through a `GroupCallSession` —
/// which needs a Client, a Room and a VoIP instance to build, so the rules would go
/// untested.
///
/// Rule one: announcements are idempotent. The SDK calls `handleNewGroupCall` both
/// when it discovers a remote membership and when we enter a call ourselves, so
/// treating each invocation as a new call produces duplicate UI.
///
/// Rule two: busy is sticky until the last call ends. The SDK reads `canHandleNewCall`
/// to decide whether to accept an incoming call; if this clears early, a second call
/// interrupts a live one.
class CallPresence {
  final Set<String> _live = {};

  /// Records a call as live. Returns true only the first time a given id is seen,
  /// so callers can use it directly to decide whether to announce.
  bool add(String callId) => _live.add(callId);

  /// Records a call as finished. Returns true if it had been live.
  bool remove(String callId) => _live.remove(callId);

  bool get isBusy => _live.isNotEmpty;

  int get liveCount => _live.length;

  @visibleForTesting
  bool contains(String callId) => _live.contains(callId);
}

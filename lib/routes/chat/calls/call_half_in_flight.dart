import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Who is working on one call half right now, in THIS process.
///
/// Three places can build or send the same half: the live finish at hangup,
/// the audio resume after a kill, and the transcript outbox replay. They share
/// one deterministic transaction id per half, so the homeserver collapses a
/// duplicate send -- but two of them uploading the same recording, or one
/// building a different half than the other, is still waste or a wrong half.
/// This registry decides who does the work; the durable stores decide what is
/// left to do.
///
/// Process-local and deliberately not persisted: a restart starts empty, which
/// is exactly right, because nothing from the previous process is still
/// working. Every claim is paired with its release in ONE try/finally at the
/// site that took it, and every await inside that scope is deadline-bounded,
/// so a claim is always released within a bound -- it never waits on network
/// work that cannot be aborted.
class CallHalfInFlight {
  CallHalfInFlight._();

  static final Map<String, ClaimToken> _held = {};

  /// A fresh token when [txnId] was free, or null when someone else holds it
  /// (skip this pass; the next trigger retries).
  static ClaimToken? claim(String txnId) {
    if (_held.containsKey(txnId)) return null;
    final token = ClaimToken._(txnId);
    _held[txnId] = token;
    return token;
  }

  /// Releases [token]'s claim, but only if that same token still holds it --
  /// a stale or repeated release can never drop a newer claim.
  static void release(ClaimToken? token) {
    if (token == null) return;
    if (identical(_held[token.txnId], token)) _held.remove(token.txnId);
  }

  static bool isClaimed(String txnId) => _held.containsKey(txnId);

  @visibleForTesting
  static void resetForTest() => _held.clear();
}

/// One holder's claim on a half. Identity, not value, is what release checks.
class ClaimToken {
  final String txnId;
  ClaimToken._(this.txnId);
}

/// One network attempt at a half. Goes dead the moment its scope is left --
/// completed, parked, canceled or thrown -- so a network future that settles
/// AFTER its attempt was abandoned can tell, and does nothing but log.
///
/// Carried in a zone value too, so a sender several layers down (the
/// transcript outbox's guard) can check it without every signature in between
/// having to thread it through.
class AttemptToken {
  bool live = true;

  static const _zoneKey = #pangeaCallHalfAttempt;

  /// The attempt the current zone runs in, or null outside any attempt.
  static AttemptToken? get current => Zone.current[_zoneKey] as AttemptToken?;

  /// Runs [body] with this token as [current].
  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_zoneKey: this});
}

/// A deadline won a bounded race: the half is parked, its claim released, and
/// whatever durable state the last completed write left is what the next
/// trigger resumes from.
class CallHalfParked implements Exception {
  final String step;
  const CallHalfParked(this.step);

  @override
  String toString() => 'CallHalfParked: $step';
}

/// The deadline for one LOCAL effect inside a claim (a sidecar write, a
/// SharedPreferences write, an outbox remove). Local, so normally milliseconds;
/// bounded anyway so a wedged disk cannot hold a claim.
const kCallHalfLocalDeadline = Duration(seconds: 5);

/// The deadline for one network round trip that is not an upload (a send, a
/// room read).
const kCallHalfNetworkDeadline = Duration(seconds: 60);

/// The upload budget across one session (live finish or one resume pass).
const kCallAudioUploadSessionBudget = Duration(minutes: 10);

/// The bound on ONE upload attempt: a minute plus the bytes at 64 KB/s, capped
/// at five minutes -- a slow phone link still gets its chance, and a stalled
/// one cannot eat the whole session.
Duration callAudioUploadAttemptBound(int bytes) {
  final scaled = Duration(seconds: 60 + bytes ~/ (64 * 1024));
  const cap = Duration(minutes: 5);
  return scaled > cap ? cap : scaled;
}

/// Awaits [work], but only until [deadline] (throws [CallHalfParked]) or until
/// [canceled] completes (throws whatever [onCanceled] returns), whichever is
/// first.
///
/// The loser is never awaited again here and keeps running -- nothing in this
/// app can abort an HTTP request mid-flight -- so callers put every effect that
/// depends on the result AFTER this returns, never in a callback on [work].
///
/// [attempt], when given, goes dead SYNCHRONOUSLY the instant the deadline or
/// the cancellation wins, so a [work] that settles a moment later already
/// sees its attempt abandoned.
Future<T> raceBounded<T>(
  Future<T> work, {
  required Duration deadline,
  required String step,
  Future<void>? canceled,
  Object Function()? onCanceled,
  AttemptToken? attempt,
}) {
  final done = Completer<T>();
  final timer = Timer(deadline.isNegative ? Duration.zero : deadline, () {
    if (!done.isCompleted) {
      attempt?.live = false;
      done.completeError(CallHalfParked(step));
    }
  });
  work.then(
    (value) {
      if (!done.isCompleted) done.complete(value);
    },
    onError: (Object e, StackTrace s) {
      if (!done.isCompleted) done.completeError(e, s);
    },
  );
  if (canceled != null) {
    canceled.then((_) {
      if (!done.isCompleted) {
        attempt?.live = false;
        done.completeError(onCanceled?.call() ?? CallHalfParked(step));
      }
    }, onError: (Object _, StackTrace _) {});
  }
  return done.future.whenComplete(timer.cancel);
}

/// [raceBounded] with the local-effect deadline.
Future<T> boundedLocal<T>(Future<T> work, String step) =>
    raceBounded(work, deadline: kCallHalfLocalDeadline, step: step);

/// A countdown for one session's upload budget.
class CallHalfBudget {
  final Duration total;
  final Stopwatch _clock = Stopwatch()..start();

  CallHalfBudget(this.total);

  Duration get remaining {
    final left = total - _clock.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// The smaller of [bound] and what is left.
  Duration cap(Duration bound) => bound < remaining ? bound : remaining;
}

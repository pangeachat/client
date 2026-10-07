import 'dart:async';
import 'dart:math' as math;

import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// The call's identity and its clock, as a device that did not ring and was
/// not rung learns them (client#9173).
///
/// Two pieces, both written by devices already in the call and read by any
/// device that joins it later:
///
/// * `pangea.call_in_progress` -- own-account ROOM ACCOUNT DATA naming the call
///   key. A learner moving a call from their phone to their laptop has no ring
///   on the laptop to learn the key from, so before this the laptop published
///   its transcript and audio under no key at all. Account data is private to
///   the account, so only the learner's own devices ever read it.
/// * `pangea.call_clock` -- a write-once timeline event relating to the call
///   key that states when the call began on the SFU's clock. Every device
///   (peer, sibling, rejoined) converts it through its own [ClockAnchor] and so
///   shows the same elapsed time instead of counting from its own first
///   sighting of the other person.

/// `pangea.call_in_progress`: what one of this account's devices in the call
/// says the call key is.
class CallInProgress {
  static const type = 'pangea.call_in_progress';

  /// The caller's membership event id -- the anchor every call half relates to.
  final String callKey;

  /// Who placed the call (the tie-break winner on glare), so a device that
  /// adopts the key also names the right caller on any card it writes.
  final String? callerId;

  /// The device that wrote this, and the membership it was in the call with.
  /// A joiner trusts the key only while that membership is still current and
  /// that device is in the SFU beside it.
  final String writerDeviceId;
  final String writerMembershipEventId;

  const CallInProgress({
    required this.callKey,
    required this.callerId,
    required this.writerDeviceId,
    required this.writerMembershipEventId,
  });

  Map<String, Object?> toJson() => {
    'call_key': callKey,
    if (callerId != null) 'caller_id': callerId,
    'writer_device_id': writerDeviceId,
    'writer_membership_event_id': writerMembershipEventId,
  };

  /// Null for anything that does not carry all three required strings: a
  /// partial record names no call a joiner could safely adopt.
  static CallInProgress? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final key = _nonEmpty(json['call_key']);
    final device = _nonEmpty(json['writer_device_id']);
    final membership = _nonEmpty(json['writer_membership_event_id']);
    if (key == null || device == null || membership == null) return null;
    return CallInProgress(
      callKey: key,
      callerId: _nonEmpty(json['caller_id']),
      writerDeviceId: device,
      writerMembershipEventId: membership,
    );
  }

  /// Whether a device joining the call may adopt [data]'s key.
  ///
  /// Two ways, and only two:
  ///
  /// * the writer is one of this account's devices the SFU names in the call
  ///   RIGHT NOW and the membership it wrote with is still current -- so the
  ///   record describes the call that is live, not one that ended in this room
  ///   earlier (the call id is the room id, so nothing else tells them apart);
  /// * this device is REJOINING and the record is its own, written with the
  ///   very membership the rejoin returns to.
  static bool accepts({
    required CallInProgress data,
    required Iterable<String> siblingDeviceIdsInSfu,
    required bool Function(String membershipEventId) isCurrentOwnMembership,
    required String? myDeviceId,
    required String? rejoinAnchor,
  }) {
    if (rejoinAnchor != null &&
        data.writerDeviceId == myDeviceId &&
        data.writerMembershipEventId == rejoinAnchor) {
      return true;
    }
    return siblingDeviceIdsInSfu.contains(data.writerDeviceId) &&
        isCurrentOwnMembership(data.writerMembershipEventId);
  }
}

/// The key a joiner falls back to when no account-data record can be adopted:
/// the LATEST ring in the room whose membership is still current for whoever
/// sent it. A ring names the caller's membership; a current membership means
/// that call is still being held. Null when no ring qualifies -- the joiner
/// then has no key, exactly as before this existed.
({String key, String caller})? keyFromCurrentRing(
  Iterable<Event> events,
  bool Function(String senderId, String membershipEventId) isCurrent,
) {
  ({String key, String caller, DateTime at})? best;
  for (final event in events) {
    if (event.type != PangeaEventTypes.callNotification) continue;
    final ring = IncomingCallNotification(
      event: event,
      myUserId: '',
      alreadyJoined: false,
    );
    final key = ring.membershipEventId;
    if (!ring.isCall || !ring.isRing || key == null) continue;
    if (!isCurrent(event.senderId, key)) continue;
    if (best == null || event.originServerTs.isAfter(best.at)) {
      best = (key: key, caller: event.senderId, at: event.originServerTs);
    }
  }
  return best == null ? null : (key: best.key, caller: best.caller);
}

/// `pangea.call_clock`: when the call began, on the SFU's clock.
class CallClockContent {
  /// Event type and relation type are the same string, the convention every
  /// other call event here follows.
  static const type = 'pangea.call_clock';

  final String callKey;

  /// The later of the two accounts' earliest SFU joins -- the moment both
  /// people were first in the call -- as the writer saw it.
  final int epochSfuMs;

  /// Provenance: the writing device and the membership it was in the call
  /// with. For the primary writer [writerAnchorId] IS the call key.
  final String writerDeviceId;
  final String writerAnchorId;

  const CallClockContent({
    required this.callKey,
    required this.epochSfuMs,
    required this.writerDeviceId,
    required this.writerAnchorId,
  });

  Map<String, Object?> toContent() => {
    'call_key': callKey,
    'epoch_sfu_ms': epochSfuMs,
    'writer_device_id': writerDeviceId,
    'writer_anchor_id': writerAnchorId,
    'm.relates_to': {'rel_type': type, 'event_id': callKey},
  };

  /// Null unless every field is present and the epoch is a believable time.
  static CallClockContent? fromJson(Map<String, Object?> json) {
    final key = _nonEmpty(json['call_key']);
    final epoch = json['epoch_sfu_ms'];
    final device = _nonEmpty(json['writer_device_id']);
    final anchor = _nonEmpty(json['writer_anchor_id']);
    final relation = json['m.relates_to'];
    if (key == null || device == null || anchor == null) return null;
    if (epoch is! int || epoch <= 0 || epoch >= ClockAnchor.clockCeilingMs) {
      return null;
    }
    if (relation is! Map ||
        relation['rel_type'] != type ||
        relation['event_id'] != key) {
      return null;
    }
    return CallClockContent(
      callKey: key,
      epochSfuMs: epoch,
      writerDeviceId: device,
      writerAnchorId: anchor,
    );
  }

  /// One transaction id per (call, sender, device), so a retry collapses onto
  /// the first send. Every interior field is length-framed: Matrix ids and
  /// event ids can hold the separator, and unframed fields could rebuild a
  /// different tuple.
  static String txnId(String callKey, String senderId, String deviceId) =>
      'pangea.call_clock:'
      '${callKey.length}:$callKey:'
      '${senderId.length}:$senderId:'
      '${deviceId.length}:$deviceId';

  /// The epoch from the SFU join stamps the writer can see: the later of the
  /// two accounts' EARLIEST joins. Null until both accounts have a stamp.
  static int? epochFromJoins(
    Iterable<int> ownAccountJoinsMs,
    Iterable<int> peerAccountJoinsMs,
  ) {
    if (ownAccountJoinsMs.isEmpty || peerAccountJoinsMs.isEmpty) return null;
    return math.max(
      ownAccountJoinsMs.reduce(math.min),
      peerAccountJoinsMs.reduce(math.min),
    );
  }

  /// One participant's SFU join in milliseconds: the stamp store's reading,
  /// refined to the millisecond where field 17 vouches for it, else the
  /// roster's whole-second SFU join time. Null when the SFU said neither.
  static int? sfuJoinMs(
    ({int secondsMs, int ms})? stamps,
    DateTime? rosterJoinedAt,
  ) {
    if (stamps != null && stamps.secondsMs > 0) {
      return ClockAnchor.millisecondRefinement(stamps.secondsMs, stamps.ms) ??
          stamps.secondsMs;
    }
    return rosterJoinedAt?.millisecondsSinceEpoch;
  }

  /// Whether this device is the primary writer: the one device whose own call
  /// membership IS the call key. A sibling that took the call over has a
  /// different membership and never qualifies; a REJOINED device does not
  /// write either -- it cannot know what it wrote before it died, and the
  /// fallback writer covers a primary that never landed.
  static bool isPrimaryWriter({
    required String callKey,
    required String? ownAnchorId,
    required bool rejoined,
  }) => !rejoined && ownAnchorId == callKey;

  /// Whether this device is the fallback writer: on the account that did NOT
  /// place the call, its own membership current, and first by device id among
  /// its account's devices in the call -- so exactly one device qualifies. A
  /// rejoined device never writes, for the primary's reason: its own SFU join
  /// is the rejoin, so the epoch it could form is too late.
  static bool isFallbackWriter({
    required bool rejoined,
    required String? callerId,
    required String? myUserId,
    required String? myDeviceId,
    required Iterable<String> siblingDeviceIds,
    required bool ownMembershipCurrent,
  }) {
    if (callerId == null || myUserId == null || myDeviceId == null) {
      return false;
    }
    if (rejoined || myUserId == callerId || !ownMembershipCurrent) {
      return false;
    }
    return siblingDeviceIds.every((d) => myDeviceId.compareTo(d) < 0);
  }
}

/// Whether a clock event's provenance holds.
enum ClockProvenance { valid, invalid, pending }

/// A clock event as the reader judges it.
class CallClockCandidate {
  final String eventId;
  final String senderId;
  final DateTime originServerTs;
  final CallClockContent content;
  final ClockProvenance provenance;

  const CallClockCandidate({
    required this.eventId,
    required this.senderId,
    required this.originServerTs,
    required this.content,
    required this.provenance,
  });

  bool get isPrimary =>
      provenance == ClockProvenance.valid &&
      content.writerAnchorId == content.callKey;
}

/// Judges one clock event against the membership event its writer names.
///
/// VALID iff the sender is a member of this direct chat AND the membership
/// event [CallClockContent.writerAnchorId] exists, was sent by the same
/// account, and carries a membership for [CallClockContent.writerDeviceId] in
/// this room's call. [membership] null means the server does not have it
/// (invalid); [fetchFailed] means it could not be looked up (pending). A
/// pending event is never chosen, and is judged again on the next refresh.
ClockProvenance judgeClockProvenance({
  required String clockSenderId,
  required CallClockContent content,
  required Set<String> dmMembers,
  required String? callId,
  required Event? membership,
  required bool fetchFailed,
}) {
  if (!dmMembers.contains(clockSenderId)) return ClockProvenance.invalid;
  if (fetchFailed || callId == null) return ClockProvenance.pending;
  if (membership == null) return ClockProvenance.invalid;
  if (membership.type != EventTypes.GroupCallMember ||
      membership.senderId != clockSenderId) {
    return ClockProvenance.invalid;
  }
  final raw = membership.content['memberships'];
  final entries = raw is List ? raw : [membership.content];
  for (final entry in entries) {
    if (entry is! Map) continue;
    if (entry['device_id'] == content.writerDeviceId &&
        entry['call_id'] == callId) {
      return ClockProvenance.valid;
    }
  }
  return ClockProvenance.invalid;
}

/// The ONE clock event every device settles on, from the same relations read:
/// among VALID events, a primary writer's first, then the earliest server
/// timestamp, then the smallest event id. Null when none is valid. A second
/// event (a fallback writer racing a late primary) is ignored by the order,
/// never averaged.
CallClockCandidate? chooseCallClock(Iterable<CallClockCandidate> candidates) {
  CallClockCandidate? best;
  for (final c in candidates) {
    if (c.provenance != ClockProvenance.valid) continue;
    if (best == null || _clockSortsBefore(c, best)) best = c;
  }
  return best;
}

bool _clockSortsBefore(CallClockCandidate a, CallClockCandidate b) {
  if (a.isPrimary != b.isPrimary) return a.isPrimary;
  final byTs = a.originServerTs.compareTo(b.originServerTs);
  if (byTs != 0) return byTs < 0;
  return a.eventId.compareTo(b.eventId) < 0;
}

/// Drives both pieces for one call on one device. Every side effect is a seam,
/// so the rules are testable without a homeserver.
class CallKeyClock {
  CallKeyClock({
    required this.writeCallInProgress,
    required this.sendClock,
    required this.fetchClockEvents,
    required this.fetchEvent,
    required this.clockArrivals,
    required this.onEpoch,
    required this.dmMembers,
    required this.callId,
    this.fallbackAfter = const Duration(seconds: 30),
    this.retryAfter = const Duration(seconds: 10),
  });

  /// Writes this account's `pangea.call_in_progress` for the room.
  final Future<void> Function(Map<String, Object?> content) writeCallInProgress;

  /// Sends a `pangea.call_clock` event under [txnId].
  final Future<void> Function(Map<String, Object?> content, String txnId)
  sendClock;

  /// Every clock event relating to the call key. Throws when it could not
  /// look.
  final Future<List<MatrixEvent>> Function(String callKey) fetchClockEvents;

  /// One event by id: null when the server does not have it, a throw when the
  /// fetch failed.
  final Future<Event?> Function(String eventId) fetchEvent;

  /// Fires when a new clock event for this room may have arrived.
  final Stream<void> clockArrivals;

  /// Called with the chosen epoch whenever the choice changes.
  final void Function(int epochSfuMs) onEpoch;

  final Set<String> Function() dmMembers;
  final String? Function() callId;
  final Duration fallbackAfter;

  /// How soon a read that could not judge every event (a failed fetch, a
  /// writer membership that could not be looked up) is tried again.
  final Duration retryAfter;
  Timer? _retryTimer;

  String? _key;
  String? _accountDataWrittenFor;
  bool _primaryAttempted = false;
  bool _fallbackAttempted = false;
  Timer? _fallbackTimer;
  StreamSubscription<void>? _arrivals;
  String? _chosenEventId;
  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _disposed = false;
  final Set<String> _loggedInvalid = {};

  /// The epoch currently in force, or null before any clock event is chosen.
  int? get chosenEpochSfuMs => _chosenEpoch;
  int? _chosenEpoch;

  /// Records this device's key in account data. Once per membership: a rejoin
  /// re-announces, so it writes again with the membership that is now
  /// current, which is what a later joiner checks.
  void keyResolved({
    required String callKey,
    required String? callerId,
    required String writerDeviceId,
    required String writerMembershipEventId,
  }) {
    if (_disposed) return;
    _key ??= callKey;
    if (_accountDataWrittenFor == writerMembershipEventId) return;
    _accountDataWrittenFor = writerMembershipEventId;
    final record = CallInProgress(
      callKey: callKey,
      callerId: callerId,
      writerDeviceId: writerDeviceId,
      writerMembershipEventId: writerMembershipEventId,
    );
    unawaited(
      writeCallInProgress(record.toJson()).catchError((Object e, StackTrace s) {
        Logs().w('Could not record the call key for other devices', e, s);
      }),
    );
  }

  /// The other person is here: write the clock if this device is the primary
  /// writer, arm the fallback, and start reading.
  ///
  /// [epochSfuMs] is read lazily and only by a writer.
  void peerArrived({
    required String callKey,
    required bool isPrimaryWriter,
    required bool Function() isFallbackWriter,
    required int? Function() epochSfuMs,
    required String writerSenderId,
    required String writerDeviceId,
    required String? Function() writerAnchorId,
  }) {
    if (_disposed) return;
    _key ??= callKey;
    if (_arrivals == null) {
      _arrivals = clockArrivals.listen((_) => unawaited(refresh()));
      unawaited(refresh());
    }
    if (isPrimaryWriter && !_primaryAttempted) {
      // Consumed only once a write actually goes out: the peer's join stamp
      // can trail its arrival by a frame, and the next change retries.
      _primaryAttempted = _write(
        epochSfuMs(),
        writerSenderId,
        writerDeviceId,
        writerAnchorId(),
        'primary',
      );
    }
    if (_fallbackTimer == null) {
      _armFallback(
        fallbackAfter,
        firstCheck: true,
        isFallbackWriter: isFallbackWriter,
        epochSfuMs: epochSfuMs,
        writerSenderId: writerSenderId,
        writerDeviceId: writerDeviceId,
        writerAnchorId: writerAnchorId,
      );
    }
  }

  /// The fallback write, [fallbackAfter] after the first peer arrival when no
  /// valid clock is in force. When it cannot write yet -- not the fallback
  /// writer right now, or no epoch formable -- it checks again every
  /// [retryAfter] until a clock is chosen or the call ends. Only the first
  /// check re-reads the relations; after that the arrivals stream keeps the
  /// choice current.
  void _armFallback(
    Duration after, {
    required bool firstCheck,
    required bool Function() isFallbackWriter,
    required int? Function() epochSfuMs,
    required String writerSenderId,
    required String writerDeviceId,
    required String? Function() writerAnchorId,
  }) {
    _fallbackTimer = Timer(after, () async {
      if (_disposed || _fallbackAttempted) return;
      if (firstCheck) await refresh();
      if (_disposed || _chosenEventId != null) return;
      if (!isFallbackWriter()) {
        if (_loggedUnwritable.add('not-fallback-writer')) {
          Logs().i('No shared call clock yet; this device keeps its own start');
        }
      } else if (_write(
        epochSfuMs(),
        writerSenderId,
        writerDeviceId,
        writerAnchorId(),
        'fallback',
      )) {
        _fallbackAttempted = true;
        Logs().i('No call clock arrived; this device wrote the fallback');
        return;
      }
      _armFallback(
        retryAfter,
        firstCheck: false,
        isFallbackWriter: isFallbackWriter,
        epochSfuMs: epochSfuMs,
        writerSenderId: writerSenderId,
        writerDeviceId: writerDeviceId,
        writerAnchorId: writerAnchorId,
      );
    });
  }

  final Set<String> _loggedUnwritable = {};

  /// Sends one clock event, latching its value. False when there is nothing
  /// to send yet (no epoch, no membership), logged once per role.
  bool _write(
    int? epoch,
    String senderId,
    String deviceId,
    String? anchorId,
    String role,
  ) {
    final key = _key;
    if (key == null || epoch == null || anchorId == null) {
      if (_loggedUnwritable.add(role)) {
        Logs().w(
          'Cannot write the $role call clock yet: '
          '${epoch == null ? 'no SFU join stamps for both accounts' : 'no membership'}',
        );
      }
      return false;
    }
    final content = CallClockContent(
      callKey: key,
      epochSfuMs: epoch,
      writerDeviceId: deviceId,
      writerAnchorId: anchorId,
    );
    // The value is latched here, once: a retry inside sendClock resends these
    // same bytes under the same transaction id.
    unawaited(
      sendClock(
        content.toContent(),
        CallClockContent.txnId(key, senderId, deviceId),
      ).catchError((Object e, StackTrace s) {
        Logs().w('Could not write the $role call clock', e, s);
      }),
    );
    return true;
  }

  /// Re-reads every clock event for the call, judges each, and applies the
  /// total order. Keeps the current value when nothing valid is found or a
  /// fetch fails.
  Future<void> refresh() async {
    final key = _key;
    if (_disposed || key == null) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        await _refreshOnce(key);
      } while (_refreshAgain && !_disposed);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshOnce(String key) async {
    final List<MatrixEvent> events;
    try {
      events = await fetchClockEvents(key);
    } catch (e, s) {
      Logs().w('Could not read the call clock; keeping the current one', e, s);
      _scheduleRetry();
      return;
    }
    final members = dmMembers();
    final id = callId();
    final candidates = <CallClockCandidate>[];
    for (final event in events) {
      if (event.type != CallClockContent.type) continue;
      final content = CallClockContent.fromJson(event.content);
      if (content == null || content.callKey != key) continue;
      Event? membership;
      var failed = false;
      try {
        membership = await fetchEvent(content.writerAnchorId);
      } catch (e) {
        failed = true;
        Logs().w('Could not check a call clock writer; retrying later: $e');
      }
      final provenance = judgeClockProvenance(
        clockSenderId: event.senderId,
        content: content,
        dmMembers: members,
        callId: id,
        membership: membership,
        fetchFailed: failed,
      );
      if (provenance == ClockProvenance.invalid &&
          _loggedInvalid.add(event.eventId)) {
        Logs().w('Ignoring a call clock whose writer does not check out');
      }
      candidates.add(
        CallClockCandidate(
          eventId: event.eventId,
          senderId: event.senderId,
          originServerTs: event.originServerTs,
          content: content,
          provenance: provenance,
        ),
      );
    }
    if (_disposed) return;
    if (candidates.any((c) => c.provenance == ClockProvenance.pending)) {
      _scheduleRetry();
    }
    final chosen = chooseCallClock(candidates);
    if (chosen == null || chosen.eventId == _chosenEventId) return;
    _chosenEventId = chosen.eventId;
    _chosenEpoch = chosen.content.epochSfuMs;
    onEpoch(chosen.content.epochSfuMs);
  }

  void _scheduleRetry() {
    if (_disposed || (_retryTimer?.isActive ?? false)) return;
    _retryTimer = Timer(retryAfter, () => unawaited(refresh()));
  }

  void dispose() {
    _disposed = true;
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    unawaited(_arrivals?.cancel());
  }
}

String? _nonEmpty(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

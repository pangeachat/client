import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// Whether [update] delivered the activity-role event in its `state` block
/// rather than its timeline.
///
/// A normal role change arrives as a timeline event. The `state` block carries
/// the room's state at the START of the timeline, which is only sent when that
/// differs from what the client last saw: a limited (gap) sync, a state reset,
/// or a fork in the room's history. On a fork it can be an OLDER role event —
/// the state as some concurrent sender saw it — and the SDK applies it
/// unconditionally over the newer one it already holds (#9229).
@visibleForTesting
bool stateBlockCarriesActivityRoles(JoinedRoomUpdate update) =>
    update.state?.any((e) => e.type == PangeaEventTypes.activityRole) ?? false;

/// Keeps each room's in-memory `pangea.activity_roles` event in step with the
/// server's current state.
///
/// Every role lives in one shared state event, and a sync whose `state` block
/// replays an older copy of it silently reverts the room — a finished role
/// reads as unfinished, the session drops back to "waiting to fill" and the
/// auto-save skips it (#9229). Whenever a sync delivers the role event in its
/// `state` block, this re-reads the current event from the server and, if the
/// room holds a different one, feeds the server's event back through the
/// SDK's own sync pipeline, so memory, the local database and every role-state
/// listener all converge on it. It only ever moves a room toward server truth.
/// See activities.instructions.md, "Role state stays in step with the server".
class ActivityRolesStateRepair {
  final Client client;

  /// Reads the room's current activity-role event from the server. Injectable
  /// so the repair is testable without a homeserver.
  final Future<MatrixEvent> Function(String roomId) _fetchCurrentRoles;

  ActivityRolesStateRepair({
    required this.client,
    Future<MatrixEvent> Function(String roomId)? fetchCurrentRoles,
  }) : _fetchCurrentRoles = fetchCurrentRoles ?? _defaultFetch(client);

  static Future<MatrixEvent> Function(String roomId) _defaultFetch(
    Client client,
  ) =>
      (roomId) async => MatrixEvent.fromJson(
        await client.getRoomStateWithKey(
          roomId,
          PangeaEventTypes.activityRole,
          '',
          format: Format.event,
        ),
      );

  StreamSubscription<SyncUpdate>? _syncSub;
  bool _disposed = false;

  /// True until the first server sync of a fresh login has passed. That sync
  /// carries every room's full state in its `state` block — the server's
  /// current state, not a replay — so checking it would only send one pointless
  /// read per activity room.
  bool _awaitingInitialSync = false;

  /// Rooms owed a check against the server. A room leaves this set only when a
  /// check for it starts, so a stale state block that lands while a check is
  /// running queues another one, and a check whose read failed is put back and
  /// retried on the next server sync — a skipped check would leave the room
  /// reverted, and later syncs never resend the event.
  final Set<String> _owed = {};
  final Set<String> _running = {};
  final Map<String, int> _failedChecks = {};

  /// Consecutive failed reads after which a room is given up on until its role
  /// event arrives in a state block again.
  static const int maxFailedChecks = 5;

  void start() {
    if (_syncSub != null) return;
    _awaitingInitialSync = client.prevBatch == null;
    _syncSub = client.onSync.stream.listen(_onSync);
  }

  void dispose() {
    _disposed = true;
    _syncSub?.cancel();
    _syncSub = null;
  }

  void _onSync(SyncUpdate sync) {
    // Server syncs always carry a next_batch. Client-built updates — history
    // pages, local echoes, and this class's own repair — leave it empty, and
    // their state blocks are not a signal of divergence.
    if (sync.nextBatch.isEmpty) return;
    if (_awaitingInitialSync) {
      _awaitingInitialSync = false;
      return;
    }
    final joined = sync.rooms?.join;
    if (joined != null) {
      for (final MapEntry(key: roomId, value: update) in joined.entries) {
        if (stateBlockCarriesActivityRoles(update)) {
          _owed.add(roomId);
          _failedChecks.remove(roomId);
        }
      }
    }
    for (final roomId in _owed.toList()) {
      if (!_running.contains(roomId)) unawaited(_drain(roomId));
    }
  }

  /// Runs checks for [roomId] until it is no longer owed one.
  Future<void> _drain(String roomId) async {
    _running.add(roomId);
    try {
      while (!_disposed && _owed.remove(roomId)) {
        if (!await _check(roomId)) break;
      }
    } finally {
      _running.remove(roomId);
    }
  }

  /// Compares the room's role event with the server's and re-applies the
  /// server's when they differ. Returns false when the read failed and the
  /// room was put back to be retried on a later sync.
  Future<bool> _check(String roomId) async {
    final room = client.getRoomById(roomId);
    if (room == null || room.membership != Membership.join) return true;

    final heldAtCheck = _heldRolesEventId(room);
    final MatrixEvent current;
    try {
      current = await _fetchCurrentRoles(roomId);
    } catch (e, s) {
      if (_disposed || room.membership != Membership.join) {
        // silent-ok: the account signed out or left the room mid-read; there
        // is no room state left to keep in step.
        return true;
      }
      final failures = (_failedChecks[roomId] ?? 0) + 1;
      _failedChecks[roomId] = failures;
      final givingUp = failures >= maxFailedChecks;
      if (!givingUp) _owed.add(roomId);
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'roomId': roomId,
          'failedChecks': failures,
          'givingUp': givingUp,
        },
        level: givingUp ? SentryLevel.error : SentryLevel.warning,
      );
      return false;
    }
    _failedChecks.remove(roomId);
    if (_disposed) return true;

    // Compared inside the transaction: a real sync holds the same lock while it
    // applies events, so a newer role event it carries is visible here before
    // anything is written, and the server's copy never lands on top of it.
    try {
      await _applyIfStillStale(room, current, heldAtCheck: heldAtCheck);
    } catch (e, s) {
      if (_disposed) return true; // silent-ok: signed out mid-write.
      _owed.add(roomId);
      ErrorHandler.logError(e: e, s: s, data: {'roomId': roomId});
      return false;
    }
    return true;
  }

  Future<void> _applyIfStillStale(
    Room room,
    MatrixEvent current, {
    required String? heldAtCheck,
  }) async {
    final roomId = room.id;
    await client.database.transaction(() async {
      final heldNow = _heldRolesEventId(room);
      if (heldNow == current.eventId) return;
      // A newer role event reached the room while the read was in flight. It
      // wins; if it too arrived in a state block, it queued its own check.
      if (heldNow != heldAtCheck) return;

      ErrorHandler.logError(
        e: 'activity_roles diverged from server state; repaired',
        data: {
          'roomId': roomId,
          'heldEventId': heldNow,
          'serverEventId': current.eventId,
        },
        level: SentryLevel.warning,
      );
      await client.handleSync(
        SyncUpdate(
          nextBatch: '',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(state: [current]),
            },
          ),
        ),
      );
    });
  }

  static String? _heldRolesEventId(Room room) {
    final held = room.getState(PangeaEventTypes.activityRole);
    return held is Event ? held.eventId : null;
  }
}

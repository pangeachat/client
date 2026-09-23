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
  final Set<String> _checking = {};

  void start() {
    _syncSub ??= client.onSync.stream.listen(_onSync);
  }

  void dispose() {
    _syncSub?.cancel();
    _syncSub = null;
  }

  void _onSync(SyncUpdate sync) {
    // Server syncs always carry a next_batch. Client-built updates — history
    // pages, local echoes, and this class's own repair — leave it empty, and
    // their state blocks are not a signal of divergence.
    if (sync.nextBatch.isEmpty) return;
    final joined = sync.rooms?.join;
    if (joined == null) return;
    for (final MapEntry(key: roomId, value: update) in joined.entries) {
      if (stateBlockCarriesActivityRoles(update)) unawaited(_repair(roomId));
    }
  }

  Future<void> _repair(String roomId) async {
    if (!_checking.add(roomId)) return;
    try {
      final room = client.getRoomById(roomId);
      if (room == null || room.membership != Membership.join) return;

      final heldAtCheck = _heldRolesEventId(room);
      final current = await _fetchCurrentRoles(roomId);
      final heldNow = _heldRolesEventId(room);

      if (heldNow == current.eventId) return;
      // A newer role event reached the room while the read was in flight; it
      // wins, and if it too is stale its own state block re-triggers a check.
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
      await client.database.transaction(
        () => client.handleSync(
          SyncUpdate(
            nextBatch: '',
            rooms: RoomsUpdate(
              join: {
                roomId: JoinedRoomUpdate(state: [current]),
              },
            ),
          ),
        ),
      );
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'roomId': roomId});
    } finally {
      _checking.remove(roomId);
    }
  }

  static String? _heldRolesEventId(Room room) {
    final held = room.getState(PangeaEventTypes.activityRole);
    return held is Event ? held.eventId : null;
  }
}

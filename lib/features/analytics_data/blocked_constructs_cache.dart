import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics_data/analytics_settings_model.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// Memo for the user's blocked constructs (#8433).
///
/// `blockedConstructs` is read per token on the chat render path and once per
/// analytics data read. Uncached, every read scans every room to find the
/// analytics room and re-parses the analytics-settings state event into a
/// fresh set. This caches both:
///
///  * the analytics room, keyed by L2 and re-validated with O(1) checks —
///    the same object is still registered under its id and the room count is
///    unchanged (any join/leave forces a rescan, which is how a canonical-room
///    change surfaces);
///  * the parsed set, keyed by the identity of the settings state event — the
///    SDK installs a new event object whenever the state changes.
///
/// The room-lookup pieces are injected so the memo is testable without a
/// synced client: [AnalyticsDataService] passes the real client's
/// `getRoomById`, `rooms.length` and its analytics-room resolver.
class BlockedConstructsCache {
  String? _l2;
  Room? _room;
  int _roomCount = -1;
  StrippedStateEvent? _settingsEvent;
  Set<ConstructIdentifier> _set = const {};

  /// The blocked set for [l2]. Read-only — the returned set is shared between
  /// reads (it is unmodifiable).
  Set<ConstructIdentifier> read({
    required String? l2,
    required int roomCount,
    required Room? Function(String roomId) roomById,
    required Room? Function() resolveAnalyticsRoom,
  }) {
    if (l2 == null) return const {};

    var room = _room;
    final roomStillValid =
        room != null &&
        _l2 == l2 &&
        _roomCount == roomCount &&
        identical(roomById(room.id), room);
    if (!roomStillValid) {
      room = resolveAnalyticsRoom();
      _room = room;
      _l2 = l2;
      _roomCount = roomCount;
    }
    if (room == null) return const {};

    final event = room.getState(PangeaEventTypes.analyticsSettings);
    if (event == null) return const {};
    if (!identical(event, _settingsEvent)) {
      _set = Set.unmodifiable(
        AnalyticsSettingsModel.fromJson(event.content).blockedConstructs,
      );
      _settingsEvent = event;
    }
    return _set;
  }

  void clear() {
    _l2 = null;
    _room = null;
    _roomCount = -1;
    _settingsEvent = null;
    _set = const {};
  }
}

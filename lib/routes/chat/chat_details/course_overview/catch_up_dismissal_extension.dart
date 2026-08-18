import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// The Catch up card's dismissal layer (#8357 "Mark all read"): the knocks
/// the user dismissed FROM THE CARD ONLY — they stay pending everywhere else
/// in the UI (member list, invite page).
///
/// Stored as per-room account data on the course space (not local storage)
/// so dismissals roam across devices and survive cache clears, arriving back
/// through /sync like the card's other inputs; and not room state, because a
/// dismissal is personal, not shared.
///
/// Keyed by [knockKey] — room + user + membership + reason — not by event ID:
/// the SDK caches members as stripped state (`requestParticipants` stores
/// `User`s, which carry no event ID), so an ID-keyed set could never match.
/// A re-knock with the same reason therefore reads as the same request; a
/// resolved knock (accepted → invite, denied → kick) drops out of the pending
/// set and its stale key is pruned on the next write.
extension CatchUpDismissalExtension on Room {
  static const String _keysKey = 'keys';

  /// The stable identity of one pending knock, for the dismissed set.
  static String knockKey(Room room, User user) =>
      '${room.id}|${user.id}|${user.membership.name}|'
      '${user.content['reason'] ?? ''}';

  Set<String> get dismissedCatchUpKeys {
    final content = roomAccountData[PangeaEventTypes.dismissedCatchUp]?.content;
    final keys = content?[_keysKey];
    if (keys is! List) return {};
    return keys.whereType<String>().toSet();
  }

  /// Adds [keys] to the dismissed set. Entries not in [pendingKeys] (their
  /// knock resolved, so they can never match again) are pruned on the way,
  /// keeping the account data to a handful of live keys.
  Future<void> dismissCatchUpNotifications(
    Set<String> keys, {
    required Set<String> pendingKeys,
  }) async {
    final next = {...dismissedCatchUpKeys.intersection(pendingKeys), ...keys};
    await client.setAccountDataPerRoom(
      client.userID!,
      id,
      PangeaEventTypes.dismissedCatchUp,
      {_keysKey: next.toList()},
    );
  }
}

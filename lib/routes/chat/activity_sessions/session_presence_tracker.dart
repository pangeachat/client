import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';

/// Live online presence for a set of users — the join list's open-session
/// members and the waiting room's coursemates — so those surfaces can sort by,
/// count and show who is around (#9333 prototype). Each user is fetched once;
/// after that only the SDK's presence stream updates it, since a re-fetch
/// returns the SDK's cached value anyway.
class SessionPresenceTracker extends ChangeNotifier {
  final Client client;
  final Map<String, CachedPresence> _presences = {};
  final Set<String> _watched = {};
  late final StreamSubscription<CachedPresence> _sub;

  SessionPresenceTracker(this.client) {
    _sub = client.onPresenceChanged.stream
        .where((p) => _watched.contains(p.userid))
        .listen(_update);
  }

  /// Start tracking [userIds] (the bot is ignored); already-tracked ids are
  /// not refetched.
  void watch(Iterable<String> userIds) {
    for (final id in userIds) {
      if (id == BotName.byEnvironment || !_watched.add(id)) continue;
      client.fetchCurrentPresence(id).then(_update);
    }
  }

  void _update(CachedPresence presence) {
    _presences[presence.userid] = presence;
    notifyListeners();
  }

  /// The most recent moment any of [userIds] was seen online, or null when
  /// none of their presence is known.
  DateTime? lastActiveOf(Iterable<String> userIds) {
    DateTime? latest;
    for (final id in userIds) {
      final at = _presences[id]?.lastSeenAt;
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    return latest;
  }

  /// How many of [userIds] are online right now — the same rule as the green
  /// presence dot on an avatar.
  int onlineCount(Iterable<String> userIds) =>
      userIds.where((id) => _presences[id]?.presence.isOnline ?? false).length;

  /// Most recent first, unknown last — the order every presence-sorted list
  /// uses.
  static int compareRecentFirst(DateTime? a, DateTime? b) {
    if (a == b) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

extension on CachedPresence {
  /// Now for someone currently active, else their last active time.
  DateTime? get lastSeenAt =>
      currentlyActive == true ? DateTime.now() : lastActiveTimestamp;
}

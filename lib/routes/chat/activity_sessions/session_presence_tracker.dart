import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';

/// Online presence for the members of the join list's open sessions, so the
/// list can sort by and show when each session was last active. A non-member
/// can't read a session's timeline, so presence is the closest signal to
/// "will anyone answer" (#9333 prototype).
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

  /// The most recent moment any of [userIds] was online, or null when none
  /// of their presence is known.
  DateTime? lastActiveOf(Iterable<String> userIds) {
    DateTime? latest;
    for (final id in userIds) {
      final presence = _presences[id];
      if (presence == null) continue;
      final at = presence.currentlyActive == true
          ? DateTime.now()
          : presence.lastActiveTimestamp;
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    return latest;
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

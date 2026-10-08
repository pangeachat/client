import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Live online presence for a set of users — the join list's open-session
/// members and the waiting room's coursemates — so those surfaces can sort by,
/// count and show who is around (#9333). Each user is fetched once;
/// after that only the SDK's presence stream updates it, since a re-fetch
/// returns the SDK's cached value anyway.
class SessionPresenceTracker extends ChangeNotifier {
  final Client client;
  final Map<String, CachedPresence> _presences = {};
  final Set<String> _watched = {};
  late final StreamSubscription<CachedPresence> _sub;
  bool _disposed = false;

  SessionPresenceTracker(this.client) {
    _sub = client.onPresenceChanged.stream
        .where((p) => _watched.contains(p.userid))
        .listen(_update);
  }

  /// Start tracking [userIds] (the bot is ignored); already-tracked ids are
  /// not refetched. The first read of the new ids lands as one batch — one
  /// rebuild, not one per user. [cachedOnly] reads only presence the client
  /// already holds (sync keeps it current for anyone sharing a room), so a
  /// large course costs no request per member.
  Future<void> watch(
    Iterable<String> userIds, {
    bool cachedOnly = false,
  }) async {
    final added = [
      for (final id in userIds)
        if (id != BotName.byEnvironment && _watched.add(id)) id,
    ];
    if (added.isEmpty) return;
    try {
      final presences = await Future.wait(
        added.map(
          (id) =>
              client.fetchCurrentPresence(id, fetchOnlyFromCached: cachedOnly),
        ),
      );
      if (_disposed) return;
      for (final presence in presences) {
        _presences[presence.userid] = presence;
      }
      notifyListeners();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'users': added.length},
        level: SentryLevel.warning,
      );
    }
  }

  void _update(CachedPresence presence) {
    if (_disposed) return;
    _presences[presence.userid] = presence;
    notifyListeners();
  }

  /// The most recent moment any of [userIds] was seen online, or null when
  /// none of their presence is known.
  DateTime? lastActiveOf(Iterable<String> userIds, {DateTime? now}) {
    now ??= DateTime.now();
    DateTime? latest;
    for (final id in userIds) {
      final at = _presences[id]?.lastSeenAt(now);
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    return latest;
  }

  /// How many of [userIds] are online right now — the same rule as the green
  /// presence dot on an avatar.
  int onlineCount(Iterable<String> userIds) =>
      userIds.where((id) => _presences[id]?.presence.isOnline ?? false).length;

  /// Most recent first, unknown last — the order every presence-sorted list
  /// uses. Callers read both times against one fixed "now" (see
  /// [lastActiveOf]), so the order is consistent within a sort.
  static int compareRecentFirst(DateTime? a, DateTime? b) {
    if (a == b) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  @override
  void dispose() {
    _disposed = true;
    _sub.cancel();
    super.dispose();
  }
}

extension on CachedPresence {
  /// [now] for someone currently active, else their last active time.
  DateTime? lastSeenAt(DateTime now) =>
      currentlyActive == true ? now : lastActiveTimestamp;
}

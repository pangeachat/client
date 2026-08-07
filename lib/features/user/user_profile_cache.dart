import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

/// A process-wide memory cache of other users' **global** Matrix profiles
/// (display name + avatar url), so a card can draw a participant it holds
/// nothing but a user id for.
///
/// Why cards fetch a profile instead of being handed a resolved [User]: a
/// session the learner has not joined has no loaded member state — its
/// `room_preview` summary carries bare user ids, and even a local [Room] drops
/// member events under lazy loading — so a name/avatar resolved upstream from
/// room state falls back to the localpart and the default letter avatar
/// (#8192). The global profile is the one source that is always available.
///
/// [Client.getProfileFromUserId] is itself database-cached and de-duplicates
/// in-flight requests, but it is asynchronous, and a widget that awaited it on
/// every build would flash the fallback on each rebuild — the world map
/// rebuilds its markers on every pan/zoom frame. This is the synchronous layer
/// over it: [cached] answers from memory within the frame, [fetch] fills that
/// memory once.
abstract class UserProfileCache {
  static final Map<String, Profile> _profiles = {};
  static final Map<String, Future<Profile>> _requests = {};

  /// The client whose [Client.onUserProfileUpdate] feeds [_invalidations].
  /// Cached entries belong to one login; a different client means a different
  /// server view of every profile, so the memory cache resets with it.
  static Client? _listeningTo;
  static StreamSubscription<String>? _invalidations;

  /// The already-resolved profile for [userId], or null if it has never been
  /// fetched (or was invalidated). Synchronous by design — see the class doc.
  static Profile? cached(String userId) => _profiles[userId];

  /// Resolves [userId]'s profile, from memory when it is there and from the
  /// SDK (server, or its own db cache) otherwise. Concurrent calls for the
  /// same id share one request.
  static Future<Profile> fetch(Client client, String userId) {
    _listenForUpdates(client);

    final hit = _profiles[userId];
    if (hit != null) return Future.value(hit);

    return _requests[userId] ??= client
        .getProfileFromUserId(userId)
        .then((profile) {
          // Only remember a profile that resolved to something. A failed
          // lookup comes back as an all-null [Profile] rather than an error
          // (the SDK swallows it), and caching that would pin a participant to
          // the default name/avatar for the rest of the session — exactly the
          // bug this cache exists to fix.
          if (profile.displayName != null || profile.avatarUrl != null) {
            _profiles[userId] = profile;
          }
          return profile;
        })
        // Block body, NOT an arrow: [Map.remove] returns the removed future,
        // and [Future.whenComplete] awaits a future its callback returns —
        // this one, which would then be waiting on itself forever.
        .whenComplete(() {
          _requests.remove(userId);
        });
  }

  /// Subscribes to the SDK's profile-change feed so a display name or avatar
  /// changed mid-session doesn't stay stale in memory until the app restarts.
  /// Re-subscribes (and drops everything cached) when the client changes.
  static void _listenForUpdates(Client client) {
    if (identical(_listeningTo, client)) return;
    _invalidations?.cancel();
    _profiles.clear();
    _listeningTo = client;
    _invalidations = client.onUserProfileUpdate.stream.listen(_profiles.remove);
  }

  @visibleForTesting
  static void reset() {
    _invalidations?.cancel();
    _invalidations = null;
    _listeningTo = null;
    _profiles.clear();
    _requests.clear();
  }
}

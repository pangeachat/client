import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/extensions/create_room_extension.dart';

/// Opens the DM a `/invite_user/<id>` link points at (#8436) — the logic
/// behind the invite landing route (DmInviteLandingPage).
abstract class DmInviteController {
  /// In-flight opens keyed by invited user id. The landing can be entered
  /// more than once for the same link before its open completes — a
  /// competing boot-time navigation remounts it, or the `/` auth guard
  /// re-enters it from the login-bounce ferry — and every entry must await
  /// the ONE open instead of creating a second DM.
  static final Map<String, Future<String>> _inFlight = {};

  /// The DM room with [userId] — the existing one when there is one, else a
  /// newly created one — deduped per user while in flight.
  ///
  /// The existing-DM lookup reads `m.direct` account data and the room list,
  /// which a fresh login has not synced yet (the landing runs right after the
  /// login bounce), so the open waits for the client's stores and, when
  /// nothing has synced, the first sync — otherwise an existing DM would be
  /// missed and duplicated.
  static Future<String> openDirectChat(Client client, String userId) =>
      dedupeInFlight(userId, () => _findOrCreateDirectChat(client, userId));

  static Future<String> _findOrCreateDirectChat(
    Client client,
    String userId,
  ) async {
    await client.roomsLoading;
    await client.accountDataLoading;
    if (client.prevBatch == null) await client.onSync.stream.first;
    return client.createPangeaDirectChat(userId);
  }

  /// Run [open] for [userId] unless one is already in flight, in which case
  /// return that one. The entry is released when it completes, success or
  /// error, so a later link click opens afresh. Pure orchestration, so it is
  /// unit-tested with a fake [open].
  @visibleForTesting
  static Future<String> dedupeInFlight(
    String userId,
    Future<String> Function() open,
  ) => _inFlight[userId] ??= open().whenComplete(() {
    // A block body on purpose: `Map.remove` returns the removed future, and
    // `whenComplete` awaits a returned future — that would be this very
    // future waiting on itself.
    _inFlight.remove(userId);
  });
}

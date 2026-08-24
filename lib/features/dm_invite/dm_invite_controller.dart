import 'package:flutter/widgets.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/user_id_url.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Opens the DM a `/invite_user/<id>` link points at (#8436).
///
/// The invite route itself never renders: its redirect caches the invited
/// user in the login-bounce ferry (SpaceCodeRepo.dmInviteUserId) and lands
/// the user on the world map with the chat list open — so a slow first sync
/// is spent looking at the app, not a blank page. The DM is then opened from
/// INSIDE the shell by [DmInviteFerryConsumer], which calls [consumePending]
/// on mount, on every workspace navigation, and whenever [signalPending]
/// fires — the three ways an invite can become actionable (a boot or
/// post-login landing, a higher-precedence ferry entry finishing, and an
/// in-session link tap that never remounts the shell).
abstract class DmInviteController {
  /// Fires when the invite redirect has just cached a link (any login state),
  /// so an already-mounted consumer opens it without waiting for a remount.
  static final ChangeNotifier pendingSignal = _Signal();

  static void signalPending() => (pendingSignal as _Signal).fire();

  /// In-flight opens keyed by invited user id. Consumption can be triggered
  /// more than once for the same link before its open completes; every
  /// trigger must await the ONE open instead of creating a second DM.
  static final Map<String, Future<String>> _inFlight = {};

  /// One consumption at a time — the triggers above overlap freely.
  static bool _consuming = false;

  /// The invite the shell should open now — the ferried user id with the home
  /// domain re-attached (a link clicked logged out is cached as the bare
  /// localpart it rode in as, since the domain is unknown pre-login) — or null
  /// when nothing is pending. Defers behind a pending join code or activity:
  /// the ferry's precedence (PAuthGaurd.consumeCachedJoinCode) puts the DM
  /// invite last, and opening the DM over the join flow would yank the user
  /// out of it; the next workspace navigation (the join landing) re-checks.
  /// Pure over the ferry, so it is unit-tested.
  static String? pendingInviteUserId({String? domain}) {
    final cached = SpaceCodeRepo.dmInviteUserId;
    if (cached == null) return null;
    if (SpaceCodeRepo.spaceCode != null || SpaceCodeRepo.activityId != null) {
      return null;
    }
    return fullUserId(cached, domain: domain);
  }

  /// Open the pending invite's DM, if any, from a mounted shell [context]:
  /// find-or-create the DM under the standard loading dialog, then land on it
  /// over the chat list (`chats,room:<id>`), keeping the course context and
  /// right column. The ferry is spent once the DM has actually opened, or the
  /// open has definitively failed (the dialog already showed the error; a bad
  /// link must not re-fire on every landing) — never before. An own invite
  /// link (#6361) has nothing to open and just spends the ferry.
  static Future<void> consumePending(BuildContext context) async {
    if (_consuming) return;
    final userId = pendingInviteUserId();
    if (userId == null) return;
    _consuming = true;
    try {
      final client = Matrix.of(context).client;
      if (userId == client.userID) {
        await SpaceCodeRepo.clearDmInviteUserId();
        return;
      }
      final result = await showFutureLoadingDialog(
        context: context,
        future: () => openDirectChat(client, userId),
      );
      await SpaceCodeRepo.clearDmInviteUserId();
      final roomId = result.result;
      if (roomId == null || !context.mounted) return;
      final router = GoRouter.of(context);
      final chats = WorkspaceNav.setSection(
        router.state.uri,
        const ChatsPanelToken(),
        keepRoom: false,
      );
      router.go(WorkspaceNav.openRoomById(Uri.parse(chats), roomId));
    } finally {
      _consuming = false;
    }
  }

  /// The DM room with [userId] — the existing one when there is one, else a
  /// newly created one — deduped per user while in flight.
  ///
  /// The existing-DM lookup reads `m.direct` account data and the room list,
  /// which a fresh login has not synced yet (the consumer runs right after the
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

/// A bare "something happened" notifier — [ChangeNotifier.notifyListeners]
/// is protected, so the fire lives on a subclass.
class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}

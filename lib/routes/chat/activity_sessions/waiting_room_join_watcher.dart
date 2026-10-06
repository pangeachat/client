import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';

/// Tells a learner who left their waiting room to practice that someone took
/// a seat, wherever in the app they are, with a way straight back
/// (#9333 prototype). One session at a time; it stops after announcing, when
/// the learner leaves the room, or after [_maxWatch].
class WaitingRoomJoinWatcher {
  static const Duration _maxWatch = Duration(minutes: 30);

  static StreamSubscription<SyncUpdate>? _sub;
  static Timer? _expiry;

  static void watch(Room room) {
    stop();
    final client = room.client;
    var seen = _otherSeatHolders(room);
    _sub = client.onSync.stream
        .where((s) => s.rooms?.join?.containsKey(room.id) ?? false)
        .listen((_) {
          if (room.membership != Membership.join) return stop();
          final holders = _otherSeatHolders(room);
          final joined = holders.difference(seen);
          seen = holders;
          if (joined.isEmpty) return;
          stop();
          _announce(room, joined.first);
        });
    _expiry = Timer(_maxWatch, stop);
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _expiry?.cancel();
    _expiry = null;
  }

  /// People other than you and the bot holding a seat in [room].
  static Set<String> _otherSeatHolders(Room room) => {
    for (final role
        in room.assignedRoles?.values ?? const <ActivityRoleModel>[])
      if (role.userId != room.client.userID &&
          role.userId != BotName.byEnvironment)
        role.userId,
  };

  static void _announce(Room room, String userId) {
    final context =
        FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
    if (context == null) {
      ErrorHandler.logError(
        e: 'No navigator context to announce a waiting-room join',
        data: {'roomId': room.id},
        level: SentryLevel.warning,
      );
      return;
    }
    final l10n = L10n.of(context);
    final name = room
        .unsafeGetUserFromMemoryOrFallback(userId)
        .calcDisplayname();
    ScaffoldMessenger.of(context).showSnackBarAnnounced(
      SnackBar(
        content: Text(l10n.joinedYourActivity(name)),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: l10n.backToActivity,
          onPressed: () => NavigationUtil.goToSpaceRoute(room.id, [], context),
        ),
      ),
    );
  }
}

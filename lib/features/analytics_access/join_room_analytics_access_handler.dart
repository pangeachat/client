import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/course_settings_extension.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/world/settings_page_enum.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';

/// The step after a course join. When the course requires sharing analytics,
/// its teachers are added to the learner's analytics room without asking, and
/// a snackbar says so, linking to the list of shared courses in Learning
/// settings (course-analytics-access.instructions.md, "Told, not asked").
class JoinRoomAnalyticsAccessHandler {
  final JoinResponse joinResponse;
  final Room room;

  const JoinRoomAnalyticsAccessHandler(this.joinResponse, this.room);

  /// The joined room's id. There is no question to decline, so a caller
  /// always carries on into the room.
  Future<String> handle(BuildContext context) async {
    // A teacher joining their own course shares nothing with themselves.
    if (room.requireAnalyticsAccess && !room.isRoomAdmin) {
      // In the background: landing in the course does not wait on the grant,
      // which reports its own failures.
      unawaited(room.client.grantInstructorsAnalyticsAccess(room.id));
      if (context.mounted) showAnalyticsSharedSnackbar(context, room);
    }
    return room.id;
  }

  /// Every join caller runs [handle] on the local room, so a join that outran
  /// sync skipped it. Runs it once the room lands, on the app's navigator.
  static Future<void> handleOnceSynced(
    Client client,
    String roomId, {
    @visibleForTesting BuildContext? Function()? navigatorContext,
  }) async {
    try {
      // Any later sync, not one naming the room: it may land before this
      // listens, and would not be named again.
      Room? joinedRoom() {
        final room = client.getRoomById(roomId);
        return room?.membership == Membership.join ? room : null;
      }

      if (joinedRoom() == null) {
        await client.onSync.stream.firstWhere((_) => joinedRoom() != null);
      }
      final room = joinedRoom()!;
      if (!room.isSpace || !room.requireAnalyticsAccess || room.isRoomAdmin) {
        return;
      }

      unawaited(client.grantInstructorsAnalyticsAccess(roomId));
      final context = (navigatorContext ?? _appNavigatorContext)();
      if (context != null && context.mounted) {
        showAnalyticsSharedSnackbar(context, room);
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"joining_room_id": roomId});
    }
  }

  static BuildContext? _appNavigatorContext() =>
      FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
}

/// Tells the learner their teachers in [course] can now see their learning
/// progress, with a link to the shared-courses list in Learning settings.
void showAnalyticsSharedSnackbar(BuildContext context, Room course) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  // A dialog's context cannot read GoRouterState; the router's own URI is the
  // same location.
  final router = GoRouter.maybeOf(context);
  if (messenger == null) return;
  final l10n = L10n.of(context);
  messenger.showSnackBarAnnounced(
    SnackBar(
      content: Text(
        l10n.analyticsSharedOnJoin(
          course.getLocalizedDisplayname(MatrixLocals(l10n)),
        ),
      ),
      action: router == null
          ? null
          : SnackBarAction(
              label: l10n.learningSettings,
              onPressed: () => router.go(
                WorkspaceNav.openSettings(
                  router.routeInformationProvider.value.uri,
                  page: SettingsPageEnum.learning.name,
                ),
              ),
            ),
    ),
  );
}

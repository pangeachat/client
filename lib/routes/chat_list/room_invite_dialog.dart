import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/invite_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

enum CourseInviteAction { accept, decline }

class RoomInviteDialog {
  static Future<void> show(BuildContext context, Room room) async {
    // Joining rebuilds the course lists, so the row that opened this dialog is
    // likely unmounted by the time the join lands (CLIENT-EX3). Read the route
    // now, and run everything after the join off the router's own navigator.
    final router = GoRouter.of(context);
    final uri = router.routeInformationProvider.value.uri;
    final appContext =
        router.routerDelegate.navigatorKey.currentContext ?? context;

    final resp = await showInviteDialog<CourseInviteAction>(
      context,
      title: L10n.of(context).youreInvited,
      message: room.isSpace
          ? L10n.of(context).invitedToSpace(room.name, room.creatorId ?? "???")
          : L10n.of(context).invitedToChat(room.name, room.creatorId ?? "???"),
      actions: [
        InviteDialogAction(
          label: L10n.of(context).decline,
          value: CourseInviteAction.decline,
          destructive: true,
        ),
        InviteDialogAction(
          label: L10n.of(context).accept,
          value: CourseInviteAction.accept,
        ),
      ],
    );

    switch (resp) {
      case CourseInviteAction.accept:
        final result = await showFutureLoadingDialog(
          context: appContext,
          future: room.joinKnockedRoom,
          exceptionContext: ExceptionContext.joinRoom,
        );

        final joinResp = result.result;
        if (joinResp == null) return;

        final handler = JoinRoomAnalyticsConsentHandler(joinResp, room);
        final joinedRoomId = await handler.handle(appContext);
        if (joinedRoomId == null) return;

        room.isSpace
            ? router.go(WorkspaceNav.openCourse(uri, joinedRoomId))
            : NavigationUtil.goToSpaceRoute(joinedRoomId, const [], context);
        return;
      case CourseInviteAction.decline:
        await room.leave();
        return;
      case null:
        return;
    }
  }
}

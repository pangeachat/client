import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_details/chat_download_provider.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

enum ActivityPopupMenuActions { invite, leave, download }

class ActivitySessionPopupMenu extends StatefulWidget {
  final Room room;

  const ActivitySessionPopupMenu(this.room, {super.key});

  @override
  ActivitySessionPopupMenuState createState() =>
      ActivitySessionPopupMenuState();
}

class ActivitySessionPopupMenuState extends State<ActivitySessionPopupMenu>
    with ChatDownloadProvider {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ActivityPopupMenuActions>(
      useRootNavigator: true,
      onSelected: (choice) async {
        switch (choice) {
          case ActivityPopupMenuActions.leave:
            final parentSpaceId = widget.room.courseParent?.id;
            final router = GoRouter.of(context);
            final confirmed = await showOkCancelAlertDialog(
              context: context,
              title: L10n.of(context).areYouSure,
              message: L10n.of(context).leaveRoomDescription,
              okLabel: L10n.of(context).leave,
              cancelLabel: L10n.of(context).cancel,
              isDestructive: true,
            );
            if (confirmed != OkCancelResult.ok) return;
            final result = await showFutureLoadingDialog(
              context: context,
              future: () => widget.room.leave(),
            );
            if (result.error == null) {
              router.go(
                parentSpaceId != null
                    ? '/rooms/spaces/$parentSpaceId'
                    : '/rooms',
              );
            }
            break;
          case ActivityPopupMenuActions.invite:
            context.go(
              widget.room.courseParent != null
                  ? '/rooms/spaces/${widget.room.courseParent!.id}/${widget.room.id}/invite'
                  : '/rooms/${widget.room.id}/invite',
            );
            break;
          case ActivityPopupMenuActions.download:
            downloadChatAction(widget.room.id, context);
            break;
        }
      },
      itemBuilder: (BuildContext context) => [
        PopupMenuItem<ActivityPopupMenuActions>(
          value: ActivityPopupMenuActions.invite,
          child: Row(
            children: [
              const Icon(Icons.person_add_outlined),
              const SizedBox(width: 12),
              Text(L10n.of(context).invite),
            ],
          ),
        ),
        PopupMenuItem<ActivityPopupMenuActions>(
          value: ActivityPopupMenuActions.download,
          child: Row(
            children: [
              const Icon(Icons.download_outlined),
              const SizedBox(width: 12),
              Text(L10n.of(context).download),
            ],
          ),
        ),
        PopupMenuItem<ActivityPopupMenuActions>(
          value: ActivityPopupMenuActions.leave,
          child: Row(
            children: [
              const Icon(Icons.logout_outlined),
              const SizedBox(width: 12),
              Text(L10n.of(context).leave),
            ],
          ),
        ),
      ],
    );
  }
}

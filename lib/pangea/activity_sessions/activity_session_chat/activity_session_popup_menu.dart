import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_details/chat_download_provider.dart';
import 'package:fluffychat/pangea/navigation/navigation_util.dart';

enum ActivityPopupMenuActions { invite, leave, download }

class ActivitySessionPopupMenu extends StatefulWidget {
  final Room room;
  final VoidCallback onLeave;

  const ActivitySessionPopupMenu(this.room, {required this.onLeave, super.key});

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
            widget.onLeave();
            break;
          case ActivityPopupMenuActions.invite:
            NavigationUtil.goToSpaceRoute(
              widget.room.id,
              ['invite'],
              context,
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

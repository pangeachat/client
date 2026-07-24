import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/chat_download_provider.dart';
import 'package:fluffychat/utils/navigation_util.dart';

enum ActivityPopupMenuActions { invite, leave, download }

class ActivitySessionPopupMenu extends StatefulWidget {
  final Room room;
  final VoidCallback onLeave;

  /// A completed session (finished for everyone): only Download applies; leave
  /// and invite are hidden.
  final bool isCompleted;

  const ActivitySessionPopupMenu(
    this.room, {
    required this.onLeave,
    this.isCompleted = false,
    super.key,
  });

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
            NavigationUtil.goToSpaceRoute(widget.room.id, ['invite'], context);
            break;
          case ActivityPopupMenuActions.download:
            downloadChatAction(widget.room.id, context);
            break;
        }
      },
      itemBuilder: (BuildContext context) => [
        if (!widget.isCompleted)
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
        // Any room member can download the transcript; web/desktop only for now
        // (the native mobile download path is unvalidated).
        if (kIsWeb)
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
        if (!widget.isCompleted)
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

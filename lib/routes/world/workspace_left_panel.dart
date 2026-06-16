import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/navigation/course_token_param.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'package:fluffychat/routes/settings/settings.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Renders one left-column panel token (the chat list, a live room, a course,
/// or settings) for the URL `?left=` list, mirroring [WorkspaceRightPanel].
/// Left content is the main app surface, so it fills its allocator slot rather
/// than floating as a card. The shell wraps a `room` panel in a roomId-keyed
/// GlobalKey so its ChatController repositions rather than remounts when the
/// slot moves. See `routing.instructions.md`.
class WorkspaceLeftPanel extends StatelessWidget {
  final PanelToken token;

  /// The current URL, so a peek can re-expand by mutating the `left=` list.
  final Uri currentUri;

  /// Collapsed to a thin tappable stripe (the allocator ran out of room).
  final bool peek;

  const WorkspaceLeftPanel({
    super.key,
    required this.token,
    required this.currentUri,
    this.peek = false,
  });

  @override
  Widget build(BuildContext context) {
    if (peek) {
      return Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 4,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(WorkspaceNav.openLeft(currentUri, token)),
          child: const Center(child: Icon(Icons.chevron_right)),
        ),
      );
    }

    switch (token.type) {
      case 'chats':
        return ChatList(activeChat: null, activeSpace: null);
      case 'room':
        return _room(context);
      case 'course':
        final parsed = CourseTokenParam.decode(token.param ?? '');
        return ChatDetails(
          roomId: fullRoomId(parsed.spaceLocalpart),
          activeTab: parsed.tab,
        );
      case 'settings':
      case 'profile':
        return const Settings();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _room(BuildContext context) {
    final roomId = fullRoomId(token.param ?? '');
    final room = Matrix.of(context).client.getRoomById(roomId);
    // A space has no timeline, so it must never render as a chat — drop to a
    // graceful empty state instead of spinning up a ChatController on it.
    if (room == null || room.isSpace || room.membership == Membership.leave) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            L10n.of(context).youAreNoLongerParticipatingInThisChat,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ChatPage(roomId: roomId);
  }
}

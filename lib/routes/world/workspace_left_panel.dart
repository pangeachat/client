import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'package:fluffychat/routes/world/add_course_panel.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Renders one left-column panel token (the chat list, a live room, a course,
/// or the add-course wizard) for the URL `?left=` list, mirroring
/// [WorkspaceRightPanel]. Each panel floats as a rounded, elevated card over the
/// map (the shell adds the surrounding margin), and its close control is an X on
/// desktop / a back arrow on mobile. The shell wraps a `room` panel in a
/// roomId-keyed GlobalKey so its ChatController repositions rather than remounts
/// when the slot moves. Under width pressure the allocator *folds* lower-priority
/// panels away (not drawn); a folded panel's content is one back-step away on the
/// sibling that stayed, so there is no in-panel stripe to render here. See
/// `routing.instructions.md`.
class WorkspaceLeftPanel extends StatelessWidget {
  final PanelToken token;

  /// The current URL, so a close/back can rewrite the `left=` list off it.
  final Uri currentUri;

  const WorkspaceLeftPanel({
    super.key,
    required this.token,
    required this.currentUri,
  });

  @override
  Widget build(BuildContext context) {
    // Float as a rounded, elevated card over the map (matching the right
    // column). The contained surface clips to the rounded corners; the shell
    // supplies the surrounding margin.
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      clipBehavior: Clip.antiAlias,
      child: _surface(context, FluffyThemes.isColumnMode(context)),
    );
  }

  Widget _surface(BuildContext context, bool isColumnMode) {
    switch (token.type) {
      case 'chats':
        return ChatList(activeChat: null, activeSpace: null);
      case 'room':
        return _room(context, isColumnMode);
      case 'addcourse':
        // The add-course wizard's first step (own/browse/private); each hosted
        // page carries its own header/close. See routing.instructions.md.
        return AddCoursePanel(subPath: token.param, currentUri: currentUri);
      case 'course':
        // The course's identity is the `?m=course:<id>` map filter (read via
        // activeSpaceIdFor), not the token — the token carries only the active
        // tab. A course is a map filter independent of its panel. See
        // routing.instructions.md.
        final spaceId = activeSpaceIdFor(currentUri);
        if (spaceId == null) return const SizedBox.shrink();
        return ChatDetails(
          roomId: spaceId,
          activeTab: token.param,
          embeddedCloseButton: _closeButton(context, isColumnMode),
        );
      default:
        // settings/profile moved to the right column (world_v2); a stale
        // `left=settings` token is dropped by the parser (wrong column), so it
        // never reaches here. See routing.instructions.md.
        return const SizedBox.shrink();
    }
  }

  /// The panel's close control: an X on desktop (matching the right column), a
  /// back arrow on mobile where a panel fills the screen. Both drop this token
  /// from `?left=`, closing the panel and leaving the rest of the workspace
  /// open (panels are independent — see `routing.instructions.md`).
  Widget _closeButton(BuildContext context, bool isColumnMode) {
    // A `room` is a token-only panel, so dropping its token closes it. A
    // section panel (a course) is also addressable by its path, so closing it
    // must return to the world map or the route-driven card re-renders it —
    // see WorkspaceNav.closeSection / routing.instructions.md.
    void close() => context.go(
          token.type == 'room'
              ? WorkspaceNav.closeLeft(currentUri, token)
              : WorkspaceNav.closeSection(currentUri, token),
        );
    return isColumnMode
        ? IconButton(
            icon: const Icon(Icons.close),
            tooltip: L10n.of(context).close,
            onPressed: close,
          )
        : BackButton(onPressed: close);
  }

  Widget _room(BuildContext context, bool isColumnMode) {
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
    return ChatPage(
      roomId: roomId,
      backButton: _closeButton(context, isColumnMode),
    );
  }
}

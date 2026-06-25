import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_add_course_subpage.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_chat_list_subpage.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_course_details_subpage.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_room_details_subpage.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_room_subpage.dart';
import 'package:fluffychat/routes/world/panel_card.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';

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

  /// From the allocator: this panel is the surviving detail over a folded
  /// master, so closing it reveals that master → its control is `←` not `X`.
  /// See `close_affordance`.
  final bool foldedOver;

  /// Items being shared into a chat, carried on the navigation's `extra` (they
  /// cannot ride the URL). The shell forwards them here so a `room` token opened
  /// by the share sheet pre-fills its composer, replacing the retired
  /// `/rooms/:roomid` route that read `state.extra`. See `routing.instructions.md`.
  final List<ShareItem>? shareItems;

  /// Render the panel's surface WITHOUT the floating [PanelCard] chrome — used
  /// when this panel is hosted inside another card-like container that already
  /// supplies the surface (the narrow [MobileCourseSheet], which wraps a course
  /// in a draggable bottom sheet). Avoids a card-inside-a-card. See
  /// `routing.instructions.md`.
  final bool bare;

  const WorkspaceLeftPanel({
    super.key,
    required this.token,
    required this.currentUri,
    this.foldedOver = false,
    this.shareItems,
    this.bare = false,
  });

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final Widget surface = switch (token.type) {
      'chats' => LeftPanelChatListSubpage(
        token: token,
        currentUri: currentUri,
        isColumnMode: isColumnMode,
        foldedOver: foldedOver,
      ),
      'room' || 'session' => LeftPanelRoomSubpage(
        token: token,
        currentUri: currentUri,
        isColumnMode: isColumnMode,
        foldedOver: foldedOver,
        shareItems: shareItems,
      ),
      'addcourse' => LeftPanelAddCourseSubpage(
        token: token,
        currentUri: currentUri,
        foldedOver: foldedOver,
        isColumnMode: isColumnMode,
      ),
      'course' => LeftPanelCourseDetailsSubpage(
        token: token,
        currentUri: currentUri,
        foldedOver: foldedOver,
        isColumnMode: isColumnMode,
      ),
      'coursepage' => () {
        final courseSpaceId = activeSpaceIdFor(currentUri);
        final page = token.param;
        if (courseSpaceId == null || page == null) {
          return const SizedBox.shrink();
        }
        return LeftPanelRoomDetailsSubpage(
          token: token,
          currentUri: currentUri,
          foldedOver: foldedOver,
          isColumnMode: isColumnMode,
          roomId: courseSpaceId,
          name: page.split('/').first,
        );
      }(),
      _ => const SizedBox.shrink(),
    };

    // The shared floating-card chrome (rounded, elevated, margin) every panel
    // uses — see [PanelCard]. Skipped when [bare] (the host supplies the surface).
    return bare ? surface : PanelCard(child: surface);
  }
}

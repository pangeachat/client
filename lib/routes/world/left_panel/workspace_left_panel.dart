import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/routes/world/activity_detail_panel.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_add_course_subpage.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_chat_list_subpage.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_close_button.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_course_details_subpage.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_room_details_subpage.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_room_subpage.dart';
import 'package:fluffychat/routes/world/panel_card.dart';
import 'package:fluffychat/routes/world/panel_header.dart';
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

  final Completer<String>? courseCreationCompleter;

  /// Render the panel's surface WITHOUT the floating [PanelCard] chrome — used
  /// when this panel is hosted inside another card-like container that already
  /// supplies the surface (the narrow nav widget's cavity, which hosts the
  /// focused section surface). Avoids a card-inside-a-card. See
  /// `routing.instructions.md`.
  final bool bare;

  const WorkspaceLeftPanel({
    super.key,
    required this.token,
    required this.currentUri,
    this.foldedOver = false,
    this.shareItems,
    this.courseCreationCompleter,
    this.bare = false,
  });

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final closeButton = LeftPanelCloseButton(
      token: token,
      currentUri: currentUri,
      foldedOver: foldedOver,
      isColumnMode: isColumnMode,
    );

    final Widget surface = switch (token) {
      ChatsPanelToken() => LeftPanelChatListSubpage(closeButton: closeButton),
      RoomPanelToken(param: final param) ||
      SessionPanelToken(param: final param) => LeftPanelRoomSubpage(
        param: param,
        shareItems: shareItems,
        closeButton: closeButton,
      ),
      AddCoursePanelToken() => LeftPanelAddCourseSubpage(
        param: null,
        closeButton: closeButton,
        courseCreationCompleter: courseCreationCompleter,
      ),
      AddCoursePagePanelToken(param: final param) => LeftPanelAddCourseSubpage(
        param: param,
        closeButton: closeButton,
        courseCreationCompleter: courseCreationCompleter,
      ),
      CoursePanelToken(param: final param) => LeftPanelCourseDetailsSubpage(
        param: param,
        spaceId: activeSpaceIdFor(currentUri),
        closeButton: closeButton,
      ),
      // An activity plan/preview — the immersive live-view surface before the
      // session room exists (#7385). Its identity AND session bindings (bound
      // room, launch) ride the token's structured param (ActivityToken, read
      // via activityInfoFor); the parent course rides the `?c=` context. It
      // brings its own Scaffold + close affordance (a back-arrow toward the
      // course, or an X to the map — see `activity_sessions_start_view.dart`),
      // so PanelCard just supplies the floating chrome like every other panel.
      ActivityPanelToken(param: final param) =>
        param != null
            ? LeftPanelActivityDetailsSubpage(
                param: param,
                parentSpaceId: activeSpaceIdFor(currentUri),
              )
            : SizedBox.shrink(),
      CoursePagePanelToken(param: final param) => () {
        final courseSpaceId = activeSpaceIdFor(currentUri);
        if (courseSpaceId == null) {
          return const SizedBox.shrink();
        }

        return LeftPanelRoomDetailsSubpage(
          roomId: courseSpaceId,
          param: param,
          closeButton: closeButton,
        );
      }(),
      NewPrivateChatPanelToken() => Column(
        children: [
          PanelHeader(
            leading: closeButton,
            title: L10n.of(context).newDirectMessage,
          ),
          Expanded(child: NewPrivateChat()),
        ],
      ),
      _ => const SizedBox.shrink(),
    };

    // The shared floating-card chrome (rounded, elevated, margin) every panel
    // uses — see [PanelCard]. Skipped when [bare] (the host supplies the surface).
    return bare ? surface : PanelCard(child: surface);
  }
}

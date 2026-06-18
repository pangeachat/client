import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/new_course_page.dart';
import 'package:fluffychat/features/navigation/close_affordance.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/chat_details/access/chat_access_settings_controller.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details.dart';
import 'package:fluffychat/routes/chat/chat_details/edit_course/edit_course.dart';
import 'package:fluffychat/routes/chat/chat_details/emotes/settings_emotes.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_details/permissions/chat_permissions_settings.dart';
import 'package:fluffychat/routes/chat/chat_search/chat_search_page.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'package:fluffychat/routes/world/add_course_panel.dart';
import 'package:fluffychat/widgets/matrix.dart';
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

  const WorkspaceLeftPanel({
    super.key,
    required this.token,
    required this.currentUri,
    this.foldedOver = false,
    this.shareItems,
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
        // The chat list has no header of its own; give the panel a "Chats"
        // title + close control at the top, matching the right column's card
        // chrome. The X dismisses the list to the map (← when it folds over a
        // sibling on narrow). See routing.instructions.md.
        return Column(
          children: [
            _panelHeader(context, isColumnMode, L10n.of(context).chats),
            Expanded(child: ChatList(activeChat: null, activeSpace: null)),
          ],
        );
      case 'room':
      // A completed-activity-session review renders as its actual locked chat,
      // identical to a live room (the lock is room-state, not token, driven).
      // Its distinct type only carries detail-slot exclusivity in the nav layer.
      case 'session':
        return _room(context, isColumnMode);
      case 'addcourse':
        // The add-course wizard's first step (own/browse/private); each hosted
        // page carries its own header/close. See routing.instructions.md.
        return AddCoursePanel(subPath: token.param, currentUri: currentUri);
      case 'course':
        // The course's identity is the `?m=course:<id>` map filter (read via
        // activeSpaceIdFor), not the token — the token's param is either the
        // active card tab (chat/course/participants/analytics) OR a pushed
        // management page (edit/invite/access/permissions/emotes/addcourse). A
        // course is a map filter independent of its panel. See
        // routing.instructions.md.
        final spaceId = activeSpaceIdFor(currentUri);
        if (spaceId == null) return const SizedBox.shrink();
        // A management page is a flat push on the course token; it renders its
        // own surface with the panel's `←`-back-to-card affordance. Everything
        // else is the card at the named tab.
        final management = _courseManagementPage(context, spaceId, isColumnMode);
        if (management != null) return management;
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

  /// The management sub-page params reachable as a PUSH on a course or room
  /// token (`course:<page>` flat, or `room:<id>/details/<page>` nested). Kept in
  /// one place so the renderer and the close affordance agree on what is a push.
  static const _managementPages = {
    'edit',
    'invite',
    'access',
    'permissions',
    'emotes',
    'addcourse',
  };

  /// True when this panel's param is a pushed sub-page (not the bare panel / a
  /// card tab): a `course:<management>` flat push, or a `room`/`session` token
  /// carrying a `<roomid>/<sub>` path. Such a page's close is `←` back one level
  /// (popPage), not `X` to the map. See `close_affordance`.
  bool get _isPushedSubPage {
    final page = token.param;
    if (page == null) return false;
    if (token.type == 'course') {
      return _managementPages.contains(page.split('/').first);
    }
    if (token.type == 'room' || token.type == 'session') {
      // The bare room id has no `/`; any `/` is a pushed sub-page beyond it.
      return page.contains('/');
    }
    return false;
  }

  /// The widget for a management sub-page [name] on [roomId] (a course/space or a
  /// room), with the panel's `←` [back] control in place of the widget's own
  /// route-pop. Null for an unknown name. Shared by the course card
  /// (`course:<page>`) and the room panel (`room:<id>/details/<page>`).
  Widget? _managementWidget(
    String roomId,
    String name,
    Widget back,
  ) {
    switch (name) {
      case 'edit':
        return EditCourse(roomId: roomId, embeddedCloseButton: back);
      case 'invite':
        final filter = currentUri.queryParameters['filter'];
        return PangeaInvitationSelection(
          roomId: roomId,
          initialFilter:
              filter != null ? InvitationFilter.fromString(filter) : null,
          embeddedCloseButton: back,
        );
      case 'access':
        return ChatAccessSettings(roomId: roomId, embeddedCloseButton: back);
      case 'permissions':
        return ChatPermissionsSettings(
          roomId: roomId,
          embeddedCloseButton: back,
        );
      case 'emotes':
        return EmotesSettings(roomId: roomId, embeddedCloseButton: back);
      case 'addcourse':
        return NewCoursePage(
          route: 'rooms',
          spaceId: roomId,
          embeddedCloseButton: back,
        );
    }
    return null;
  }

  /// Render a pushed course management page for [spaceId], or null when the
  /// course param is a card tab (chat/course/participants/analytics). The deeper
  /// add-a-plan step (`addcourse/<courseId>`) stays route-driven (a Completer
  /// flow). See `routing.instructions.md`.
  Widget? _courseManagementPage(
    BuildContext context,
    String spaceId,
    bool isColumnMode,
  ) {
    if (token.type != 'course') return null;
    final page = token.param;
    if (page == null || !_managementPages.contains(page.split('/').first)) {
      return null;
    }
    return _managementWidget(
      spaceId,
      page.split('/').first,
      _closeButton(context, isColumnMode),
    );
  }

  /// A panel header row — the close/back control at the leading edge plus a
  /// [title] — for section panels (the chat list) that carry no header of their
  /// own, mirroring the right column's card chrome.
  Widget _panelHeader(BuildContext context, bool isColumnMode, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          _closeButton(context, isColumnMode),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// The panel's close control. A pushed sub-page ([_isPushedSubPage]) backs out
  /// ONE level via popPage (a course management page → the card; a room sub-page
  /// → the chat). Otherwise the centralized [CloseAffordance] decides `←` (reveal
  /// a folded/sibling master) vs `X` (dismiss to the map). See
  /// `close_affordance` / `routing.instructions.md`.
  Widget _closeButton(BuildContext context, bool isColumnMode) {
    final page = token.param;
    if (_isPushedSubPage && page != null) {
      return BackButton(
        onPressed: () =>
            context.go(WorkspaceNav.popPage(currentUri, token.type, page)),
      );
    }
    // A `room`/`session` is a token-only panel, so dropping its token closes it.
    // A section panel (a course) is also addressable by its map filter, so
    // closing it returns to the world map. See WorkspaceNav.closeSection.
    void close() => context.go(
          token.type == 'room' || token.type == 'session'
              ? WorkspaceNav.closeLeft(currentUri, token)
              : WorkspaceNav.closeSection(currentUri, token),
        );
    // Centralized affordance (close_affordance.dart): `←` when closing reveals a
    // master that was behind us — a width-fold ([foldedOver]) or a narrow single
    // pane with a sibling behind it; otherwise `X` dismisses to the map.
    final hasSibling = parseOpenPanels(currentUri).left.length > 1;
    final aff = CloseAffordance.of(
      isPushedPage: false,
      revealsMaster: foldedOver || (!isColumnMode && hasSibling),
    );
    return aff.showBack
        ? BackButton(onPressed: close)
        : IconButton(
            icon: const Icon(Icons.close),
            tooltip: L10n.of(context).close,
            onPressed: close,
          );
  }

  /// A live room (or a locked `session` review) and its pushed sub-pages. The
  /// param is `<roomid>` (the chat), `<roomid>/search`, `<roomid>/invite`,
  /// `<roomid>/details`, or `<roomid>/details/<management>` — the bare id is the
  /// chat; a `/`-suffix is a sub-page push rendered with the panel's
  /// `←`-back-to-chat control, mirroring the old `/rooms/:roomid/<page>` tree.
  /// See `routing.instructions.md`.
  Widget _room(BuildContext context, bool isColumnMode) {
    final param = token.param ?? '';
    final slash = param.indexOf('/');
    final bareId = slash < 0 ? param : param.substring(0, slash);
    final sub = slash < 0 ? '' : param.substring(slash + 1);
    final roomId = fullRoomId(bareId);
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
    final back = _closeButton(context, isColumnMode);
    if (sub.isNotEmpty) {
      final page = _roomSubPage(context, roomId, sub, back);
      if (page != null) return page;
    }
    // The chat: thread the jump-to-message `?event=` (rides the URL) and any
    // shared items (ride the navigation `extra`) the retired route used to read.
    return ChatPage(
      roomId: roomId,
      eventId: currentUri.queryParameters['event'],
      shareItems: shareItems,
      backButton: back,
    );
  }

  /// The widget for a room sub-page push (`search`, `invite`, `details`, or
  /// `details/<management>`), or null to fall back to the chat. Mirrors the old
  /// `/rooms/:roomid/<page>` route tree as in-panel pushes.
  Widget? _roomSubPage(
    BuildContext context,
    String roomId,
    String sub,
    Widget back,
  ) {
    switch (sub.split('/').first) {
      case 'search':
        return ChatSearchPage(roomId: roomId, embeddedCloseButton: back);
      case 'invite':
        final filter = currentUri.queryParameters['filter'];
        return PangeaInvitationSelection(
          roomId: roomId,
          initialFilter:
              filter != null ? InvitationFilter.fromString(filter) : null,
          embeddedCloseButton: back,
        );
      case 'details':
        final rest =
            sub.contains('/') ? sub.substring(sub.indexOf('/') + 1) : '';
        if (rest.isEmpty) {
          return ChatDetails(roomId: roomId, embeddedCloseButton: back);
        }
        return _managementWidget(roomId, rest.split('/').first, back);
    }
    return null;
  }
}

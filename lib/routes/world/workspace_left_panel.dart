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

  /// From the allocator: this panel is the surviving detail over a folded
  /// master, so closing it reveals that master → its control is `←` not `X`.
  /// See `close_affordance`.
  final bool foldedOver;

  const WorkspaceLeftPanel({
    super.key,
    required this.token,
    required this.currentUri,
    this.foldedOver = false,
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

  /// The course-token params that are pushed MANAGEMENT pages (vs card tabs):
  /// each renders its own admin surface inside the course slot. Kept in one
  /// place so the renderer and the close affordance agree on what is a push.
  static const _courseManagementPages = {
    'edit',
    'invite',
    'access',
    'permissions',
    'emotes',
    'addcourse',
  };

  /// True when the course token's param is a pushed management page (its first
  /// segment is in [_courseManagementPages]) rather than a card tab. Such a
  /// page's close is `←` back to the card, not `X` to the map.
  bool get _isCourseManagementPage {
    final page = token.param;
    return token.type == 'course' &&
        page != null &&
        _courseManagementPages.contains(page.split('/').first);
  }

  /// Render a pushed course management page (edit/invite/access/permissions/
  /// emotes/addcourse) for [spaceId], or null when the course param is a card
  /// tab. Each hosted page takes the panel's `←`-back-to-card control in place
  /// of its own route-pop back. The deeper add-a-plan step
  /// (`addcourse/<courseId>`) stays route-driven (a Completer flow). See
  /// `routing.instructions.md`.
  Widget? _courseManagementPage(
    BuildContext context,
    String spaceId,
    bool isColumnMode,
  ) {
    if (!_isCourseManagementPage) return null;
    final page = token.param!;
    final back = _closeButton(context, isColumnMode);
    switch (page.split('/').first) {
      case 'edit':
        return EditCourse(roomId: spaceId, embeddedCloseButton: back);
      case 'invite':
        final filter = currentUri.queryParameters['filter'];
        return PangeaInvitationSelection(
          roomId: spaceId,
          initialFilter:
              filter != null ? InvitationFilter.fromString(filter) : null,
          embeddedCloseButton: back,
        );
      case 'access':
        return ChatAccessSettings(roomId: spaceId, embeddedCloseButton: back);
      case 'permissions':
        return ChatPermissionsSettings(
          roomId: spaceId,
          embeddedCloseButton: back,
        );
      case 'emotes':
        return EmotesSettings(roomId: spaceId, embeddedCloseButton: back);
      case 'addcourse':
        return NewCoursePage(
          route: 'rooms',
          spaceId: spaceId,
          embeddedCloseButton: back,
        );
    }
    return null;
  }

  /// The panel's close control: an X on desktop (matching the right column), a
  /// back arrow on mobile where a panel fills the screen. Both drop this token
  /// from `?left=`, closing the panel and leaving the rest of the workspace
  /// open (panels are independent — see `routing.instructions.md`).
  Widget _closeButton(BuildContext context, bool isColumnMode) {
    // A pushed course management page (`course:edit`, …) backs out ONE level to
    // the card (popPage), not a dismiss-to-map — there is always a card behind
    // it. See `close_affordance` / `routing.instructions.md`.
    if (_isCourseManagementPage) {
      final page = token.param!;
      return BackButton(
        onPressed: () =>
            context.go(WorkspaceNav.popPage(currentUri, 'course', page)),
      );
    }
    // A `room` is a token-only panel, so dropping its token closes it. A
    // section panel (a course) is also addressable by its path, so closing it
    // must return to the world map or the route-driven card re-renders it —
    // see WorkspaceNav.closeSection / routing.instructions.md.
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

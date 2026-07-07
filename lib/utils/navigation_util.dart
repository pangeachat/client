import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';

/// world_v2: everything is a token over the world map (`/`). This is the single
/// funnel the app uses to focus a room, a room sub-page, a course, or a course
/// management page — it builds the token URL and `context.go`s it. There are no
/// `/rooms/...` or `/courses/...` render paths anymore; inbound legacy paths are
/// rewritten to tokens by `legacy_redirects`. See `routing.instructions.md`.
class NavigationUtil {
  /// Close the current surface without dead-ending. A real pushed route or
  /// dialog pops normally; but a world_v2 token panel (a settings page, an
  /// analytics detail) has nothing on the navigator stack to pop to, so a bare
  /// `Navigator.pop()` falls out of the shell to the initial route and renders
  /// the loading page (#7076). When there is nothing to pop, navigate to
  /// [fallback] — a token location — instead. See `routing.instructions.md`.
  static void popOrGo(BuildContext context, String fallback) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      GoRouter.of(context).go(fallback);
    }
  }

  /// [filter] is the invite page's initial contact filter; [event] is a
  /// jump-to-message target on the room's own timeline. Both fold into the
  /// destination panel's token param (a `coursepage` page or a `room`
  /// sub-page) instead of riding as a loose query — everything a panel needs
  /// rides in its token (routing.instructions.md).
  static void goToSpaceRoute(
    String? goalRoomID,
    List<String> goalSubroute,
    BuildContext context, {
    Object? extra,
    String? filter,
    String? event,
  }) {
    final uri = GoRouterState.of(context).uri;
    final activeSpaceId = activeSpaceIdFor(uri);
    final sub = goalSubroute.join('/');

    // No room target. A bare call exits the chat: re-show the active course card
    // if a course is open, else clear to the world map. A sub-route with an
    // active course opens that management page as a `coursepage` detail beside
    // the card.
    if (goalRoomID == null) {
      if (activeSpaceId != null) {
        final coursePage = coursePageFor(sub);
        context.go(
          coursePage.isEmpty
              ? WorkspaceNav.openCourseTab(uri)
              : WorkspaceNav.openCoursePage(uri, coursePage, filter: filter),
          extra: extra,
        );
      } else {
        context.go(WorkspaceNav.clearAll(), extra: extra);
      }
      return;
    }

    // The active course SPACE itself: re-show its card, or open a management
    // page (invite / edit / …) as a `coursepage` detail beside the card. The
    // shared chat-details UI addresses these with a room-style `details/<page>`
    // subroute, so normalize to the course's bare page (see coursePageFor).
    if (activeSpaceId != null && goalRoomID == activeSpaceId) {
      final coursePage = coursePageFor(sub);
      context.go(
        coursePage.isEmpty
            ? WorkspaceNav.openCourseTab(uri)
            : WorkspaceNav.openCoursePage(uri, coursePage, filter: filter),
        extra: extra,
      );
      return;
    }

    // A specific room (a live chat, or a room within the active course). The
    // bare room is the single live left panel (openExclusiveLeftRoom keeps the
    // course filter + the right column, drops any other room). A sub-page
    // (search / details / invite / details/<management>) is a push on the room
    // token (`room:<id>/<sub>`), with [filter] folded into that sub-page and
    // [event] into the token's `e/<eventId>` field; shared items ride `extra`,
    // which the shell forwards to the room.
    final shortId = shortRoomId(goalRoomID);
    if (sub.isEmpty) {
      // The bare room is the single live left panel (one live room rule), even
      // when a one-shot jump-to-message rides along — [event] gates nothing
      // here, only the sub-page does. Entering a room also clears any
      // activity-plan overlay (`?activity=`/`roomid`/`launch`/`autoplay`): when
      // you START a session from an activity plan, the session room REPLACES the
      // plan panel rather than opening beside it. (A no-op for non-activity room
      // opens, where those params aren't set.) See routing.instructions.md.
      context.go(
        WorkspaceNav.openExclusiveLeftRoom(
          stripActivityOverlay(uri),
          PanelToken('room', RoomTokenParam(id: shortId, eventId: event)),
        ),
        extra: extra,
      );
      return;
    }

    context.go(
      WorkspaceNav.pushPage(
        uri,
        'room',
        RoomTokenParam(id: shortId, subPage: sub, filter: filter),
      ),
      extra: extra,
    );
  }

  /// Drop the activity-plan addressing from [uri] so a started/continued
  /// session REPLACES the plan rather than opening beside it: the `activity`
  /// token (whose fields carry the session bindings) and any legacy loose
  /// activity params are dropped, a standalone `/<uuid>` path collapses to the
  /// world path, and the course context survives. Delegates to
  /// [WorkspaceNav.dropActivityOverlay], the one activity-overlay sweeper. See
  /// `routing.instructions.md`.
  @visibleForTesting
  static Uri stripActivityOverlay(Uri uri) =>
      Uri.parse(WorkspaceNav.dropActivityOverlay(uri));

  /// Normalizes a room-style chat-details subroute to its course `coursepage`.
  ///
  /// The chat-details UI is shared between rooms and the course space and
  /// addresses management screens with a room-style `details/<page>` path (e.g.
  /// the participants tab invites via `['details', 'invite']`). A course has no
  /// `details` coursepage — that role is the card itself — so `details` maps to
  /// `''` (show the card) and `details/<page>` to the bare `<page>` coursepage.
  /// Any other subroute is already a bare coursepage and passes through.
  /// Without this, `details/invite` became the unhandled token
  /// `coursepage:details/invite`, rendering an empty, un-closable panel (#7099).
  @visibleForTesting
  static String coursePageFor(String sub) {
    if (sub == 'details') return '';
    if (sub.startsWith('details/')) return sub.substring('details/'.length);
    return sub;
  }
}

import 'package:flutter/widgets.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/utils/navigation_util.dart';

/// The location that closes an open room-panel token for [roomId]: it drops
/// ONLY that token, so the rest of the workspace — notably the chat list —
/// survives. Closing an activity plan (#7156) and leaving a chat (#7561) must
/// not also clear the chat list. Returns null when no such token is open (e.g.
/// the standalone `/<activityId>` route) — the caller pops or falls back.
String? roomTokenCloseLocation(Uri uri, String? roomId) {
  if (roomId == null || roomId.isEmpty) return null;

  bool matches(PanelToken t) {
    if (!t.type.isRoomPanel) return false;

    final param = t.param;
    if (param == null || param is! RoomTokenParam) return false;
    return shortRoomId(param.id) == shortRoomId(roomId);
  }

  final panels = parseOpenPanels(uri);

  for (final t in panels.left) {
    if (matches(t)) return WorkspaceNav.closeLeft(uri, t);
  }

  for (final t in panels.right) {
    if (matches(t)) return WorkspaceNav.closeRight(uri, t);
  }

  return null;
}

/// Close the open room panel for [roomId] after leaving or deleting it from a
/// surface that is NOT the room itself — a chat-list (or course-chat-list) row's
/// context menu. Drops ONLY that room's token, so the list it sits in stays open
/// and the surviving `?c=` scope decides which is revealed beneath: the chat
/// list, or the course card of a course-scoped list (#7561). When the room isn't
/// open as a panel there is nothing to close, so the workspace is left untouched
/// and the list drops the row reactively — navigating unconditionally here is
/// what closed the list before. See `routing.instructions.md`.
void closeRoomPanelFromList(BuildContext context, String roomId) {
  final close = roomTokenCloseLocation(GoRouterState.of(context).uri, roomId);
  if (close != null) context.go(close);
}

/// Close the open room panel for [roomId] after leaving or deleting it from the
/// room's OWN surface — its in-chat menu or its details page. Drops that room's
/// token so what's beneath survives (the chat list, or the course card it was
/// opened over) (#7561). Falls back to the bare workspace exit only when the room
/// isn't a token panel (a legacy pushed route), so the user is never stranded on
/// the surface of the room they just left. See `routing.instructions.md`.
void closeOwnRoomPanel(BuildContext context, String roomId) {
  final close = roomTokenCloseLocation(GoRouterState.of(context).uri, roomId);
  if (close != null) {
    context.go(close);
  } else {
    NavigationUtil.goToSpaceRoute(null, const [], context);
  }
}

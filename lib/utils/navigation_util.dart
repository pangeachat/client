import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';

class NavigationUtil {
  static void goToSpaceRoute(
    String? goalRoomID,
    List<String> goalSubroute,
    BuildContext context, {
    Object? extra,
    Map<String, String>? queryParams,
  }) {
    final currentRoute = GoRouterState.of(context);
    final uri = currentRoute.uri;
    String queryString = '';
    if (queryParams != null && queryParams.isNotEmpty) {
      queryString =
          '?${queryParams.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}';
    }

    // world_v2: a course is the `?m=course:<id>` map filter, not a path. When a
    // course filter is active, open a room within it as a left `room` token
    // beside the course panel — preserving the filter and the right column, with
    // the single-live-room rule (see WorkspaceNav.openExclusiveLeftRoom). The
    // course root, the space itself, or a deeper sub-route fall back to the
    // legacy `/courses/:spaceid/...` form, which the router redirects into the
    // workspace (and keeps room sub-routes route-driven). See
    // `routing.instructions.md`.
    final activeSpaceId = activeSpaceIdFor(uri);
    if (activeSpaceId != null) {
      final opensRoom = goalRoomID != null &&
          goalRoomID != activeSpaceId &&
          goalSubroute.isEmpty &&
          (queryParams == null || queryParams.isEmpty);
      if (opensRoom) {
        context.go(
          WorkspaceNav.openExclusiveLeftRoom(
            uri,
            PanelToken('room', shortRoomId(goalRoomID)),
          ),
          extra: extra,
        );
        return;
      }
      // A management page on the course ITSELF is a flat push on the course
      // token (course:edit, course:invite, …) — no path, no redirect bounce;
      // any caller query rides as a one-shot the panel reads. A deeper room
      // sub-page or the bare course root stays on the legacy path (redirected)
      // until the room push migration. See `routing.instructions.md`.
      final onCourseItself = goalRoomID == null || goalRoomID == activeSpaceId;
      if (onCourseItself && goalSubroute.isNotEmpty) {
        final loc = WorkspaceNav.pushPage(uri, 'course', goalSubroute.join('/'));
        context.go(
          queryString.isEmpty
              ? loc
              : '$loc${loc.contains('?') ? '&' : '?'}${queryString.substring(1)}',
          extra: extra,
        );
        return;
      }
      final base = PRoutes.course(activeSpaceId);
      final roomTail = (goalRoomID == null || goalRoomID == activeSpaceId)
          ? ''
          : '/$goalRoomID';
      final subTail = goalSubroute.isEmpty ? '' : '/${goalSubroute.join('/')}';
      context.go('$base$roomTail$subTail$queryString', extra: extra);
      return;
    }

    if (goalRoomID == null) {
      context.go('${PRoutes.world}$queryString', extra: extra);
      return;
    }

    if (goalSubroute.isEmpty) {
      context.go('/rooms/$goalRoomID$queryString', extra: extra);
      return;
    }

    context.go(
      '/rooms/$goalRoomID/${goalSubroute.join('/')}$queryString',
      extra: extra,
    );
  }
}

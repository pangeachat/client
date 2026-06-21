import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';

/// world_v2: everything is a token over the world map (`/`). This is the single
/// funnel the app uses to focus a room, a room sub-page, a course, or a course
/// management page — it builds the token URL and `context.go`s it. There are no
/// `/rooms/...` or `/courses/...` render paths anymore; inbound legacy paths are
/// rewritten to tokens by `legacy_redirects`. See `routing.instructions.md`.
class NavigationUtil {
  static void goToSpaceRoute(
    String? goalRoomID,
    List<String> goalSubroute,
    BuildContext context, {
    Object? extra,
    Map<String, String>? queryParams,
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
        context.go(
          sub.isEmpty
              ? WorkspaceNav.openCourse(uri, const PanelToken('course'))
              : _appendQuery(
                  WorkspaceNav.openCoursePage(uri, sub),
                  queryParams,
                ),
          extra: extra,
        );
      } else {
        context.go(
          _appendQuery(WorkspaceNav.clearAll(), queryParams),
          extra: extra,
        );
      }
      return;
    }

    // The active course SPACE itself: re-show its card, or open a management
    // page (invite / edit / …) as a `coursepage` detail beside the card.
    if (activeSpaceId != null && goalRoomID == activeSpaceId) {
      context.go(
        sub.isEmpty
            ? WorkspaceNav.openCourse(uri, const PanelToken('course'))
            : _appendQuery(WorkspaceNav.openCoursePage(uri, sub), queryParams),
        extra: extra,
      );
      return;
    }

    // A specific room (a live chat, or a room within the active course). The
    // bare room is the single live left panel (openExclusiveLeftRoom keeps the
    // course filter + the right column, drops any other room). A sub-page
    // (search / details / invite / details/<management>) is a push on the room
    // token (`room:<id>/<sub>`). Any query (event/body/filter) rides alongside;
    // shared items ride `extra`, which the shell forwards to the room.
    final shortId = shortRoomId(goalRoomID);
    if (sub.isEmpty) {
      // The bare room is the single live left panel (one live room rule), even
      // when a one-shot query (event/body) rides along — the query gates
      // nothing here, only the sub-page does. Entering a room also clears any
      // activity-plan overlay (`?activity=`/`roomid`/`launch`/`autoplay`): when
      // you START a session from an activity plan, the session room REPLACES the
      // plan panel rather than opening beside it. (A no-op for non-activity room
      // opens, where those params aren't set.) See routing.instructions.md.
      context.go(
        _appendQuery(
          WorkspaceNav.openExclusiveLeftRoom(
            stripActivityOverlay(uri),
            PanelToken('room', shortId),
          ),
          queryParams,
        ),
        extra: extra,
      );
      return;
    }
    context.go(
      _appendQuery(
        WorkspaceNav.pushPage(uri, 'room', '$shortId/$sub'),
        queryParams,
      ),
      extra: extra,
    );
  }

  /// Drop the activity-plan addressing from [uri] so a started/continued session
  /// REPLACES the plan rather than opening beside it. The plan is addressed two
  /// ways (see `route_facts.activityFor`): the in-course `?activity=` query
  /// overlay AND the parentless standalone `/<uuid>` path (opened from a map
  /// pin). So drop the overlay query params (`activity`/`roomid`/`launch`/
  /// `autoplay`) AND collapse a standalone-activity path to the world path —
  /// panels are tokens over `/`, so a `left=room` left on a `/<uuid>` path would
  /// leave the plan (which renders from that path) standing beside the room. The
  /// session room is the plan's sibling: they share the activity id, so one
  /// replaces the other. Every other query part is kept **raw** so the
  /// PanelToken-encoded `m=`/`left=` values aren't re-encoded. See
  /// `routing.instructions.md`.
  @visibleForTesting
  static Uri stripActivityOverlay(Uri uri) {
    const drop = {'activity', 'roomid', 'launch', 'autoplay'};
    final segments = uri.pathSegments;
    final standaloneActivity =
        segments.length == 1 && PRoutes.isWorldObjectId(segments.first);
    final path = standaloneActivity ? PRoutes.world : uri.path;
    final kept = uri.query.isEmpty
        ? const <String>[]
        : uri.query
              .split('&')
              .where((p) => !drop.contains(p.split('=').first))
              .toList();
    return uri.replace(path: path, query: kept.isEmpty ? '' : kept.join('&'));
  }

  /// Append [queryParams] to an already-built token location (which may already
  /// carry a `?left=`/`?m=` query), choosing `?` or `&` as needed.
  static String _appendQuery(String loc, Map<String, String>? queryParams) {
    if (queryParams == null || queryParams.isEmpty) return loc;
    final q = queryParams.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
    return '$loc${loc.contains('?') ? '&' : '?'}$q';
  }
}

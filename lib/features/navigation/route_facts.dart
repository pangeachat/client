import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';

/// World_v2 routing facts — the single place navigation/layout decisions are
/// derived from a [GoRouterState]. Every consumer (the shell layout, the
/// left-column switcher, the nav rail, the bottom nav, the map) calls these
/// instead of re-deriving from path segments, so they cannot disagree.
///
/// See `routing.instructions.md` for the model and `deep-linking.instructions.md`
/// for the cross-repo contract.

/// How a route's canvas relates to the persistent world map.
enum CanvasMode {
  /// Paints nothing; the persistent map shows through (section roots).
  mapHole,

  /// Opaque panel capped at the detail width; the map peeks alongside.
  detail,

  /// Opaque content that fills the canvas (the add-course hub).
  fullBleed,
}

/// A target the map should bring into the exposed canvas. Sealed so adding a
/// new focusable content kind (a location, a course region, a world object)
/// is a compile-checked new subclass plus one `switch` arm in the map — the
/// rest of routing is unchanged.
sealed class MapFocus {
  const MapFocus();
}

/// Center the map on an activity (by id; its coordinate is resolved by the map).
class ActivityFocus extends MapFocus {
  final String activityId;
  const ActivityFocus(this.activityId);

  @override
  bool operator ==(Object other) =>
      other is ActivityFocus && other.activityId == activityId;

  @override
  int get hashCode => activityId.hashCode;
}

// Future focus kinds slot in here, e.g.:
//   class LocationFocus extends MapFocus { final LatLng latLng; ... }
//   class ObjectFocus  extends MapFocus { final String objectId; ... }
// Add the subclass, then one arm to the map's focus switch. Nothing else.

/// The learning-analytics view the top-right cluster opens, docked on the right
/// over the map via the `?analytics=<tab>` query param. A right-side overlay
/// (parallel to the left-anchored `?activity=` detail), so it coexists with the
/// map-hole world view rather than consuming the canvas. See
/// `world-user-cluster.instructions.md`.
enum AnalyticsPanelTab {
  sessions,
  grammar,
  vocab;

  String get queryValue => name;

  static AnalyticsPanelTab? fromQuery(String? value) {
    for (final tab in AnalyticsPanelTab.values) {
      if (tab.name == value) return tab;
    }
    return null;
  }
}

/// The analytics panel an open route addresses (`?analytics=<tab>`), else null.
AnalyticsPanelTab? analyticsFor(GoRouterState state) =>
    AnalyticsPanelTab.fromQuery(state.uri.queryParameters['analytics']);

/// Section roots that render as a map hole **in column mode** (their content
/// moves to the left column). In narrow mode they fill the screen instead.
/// `/` is always the map and is handled separately. This is the single source
/// for the canvas decision; `routes.dart` (`canvasPage`) and the shell layout
/// both read it, so the page builder and the layout can't drift.
const Set<String> _mapHoleColumnRoutes = {
  '/chats',
  '/rooms',
  '/courses/own',
  '/courses/browse',
  '/courses/private',
  '/courses/:spaceid',
  '/courses/:spaceid/details',
  '/analytics',
  '/analytics/morph',
  '/analytics/vocab',
  '/analytics/activities',
  '/analytics/level',
  '/settings',
  '/profile',
};

/// The add-course hub: a card that floats over the full-bleed map.
const String _fullBleedRoute = '/courses';

/// Whether [fullPath] renders as the map hole right now (the page builder uses
/// this to choose `EmptyPage` vs its content). `/` is always the map.
bool isMapHole(String? fullPath, bool isColumnMode) =>
    fullPath == PRoutes.world ||
    (isColumnMode && _mapHoleColumnRoutes.contains(fullPath));

/// The effective canvas for the current route. An open activity overlay always
/// renders as a detail panel; otherwise it follows the route's declared canvas.
CanvasMode canvasFor(GoRouterState state, bool isColumnMode) {
  if (activityFor(state) != null) return CanvasMode.detail;
  if (isMapHole(state.fullPath, isColumnMode)) return CanvasMode.mapHole;
  if (state.fullPath == _fullBleedRoute) return CanvasMode.fullBleed;
  return CanvasMode.detail;
}

/// The active top-level section. `/rooms/...` belongs to chats; first-class
/// world-object uuids render over the map (world). Unknown → world (a sane
/// nav highlight); the canvas is decided by [canvasFor], not the section, so an
/// unrecognized detail route never flips the shell to the world map.
AppSection sectionFor(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.isEmpty) return AppSection.world;
  final first = segments.first;
  if (first == 'rooms') return AppSection.chats;
  if (PRoutes.isWorldObjectId(first)) return AppSection.world;
  for (final section in AppSection.values) {
    final segment = section.rootPath == '/' ? '' : section.rootPath.substring(1);
    if (segment == first) return section;
  }
  return AppSection.world;
}

/// The active course space id (`/courses/:spaceid`), else null. Literal
/// subroutes (`preview`/`own`/`browse`/`private`) are not space ids — Matrix
/// space ids start with `!`. Gated this way, a course-room id or a literal
/// segment can never masquerade as the active space.
String? activeSpaceIdFor(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.length < 2 || segments.first != 'courses') return null;
  final second = segments[1];
  // URLs carry a bare localpart; re-attach the home server_name for callers
  // that hit the Matrix client.
  return second.startsWith('!') ? fullRoomId(second) : null;
}

/// The active chat/course room id, if the route addresses one.
String? activeRoomIdFor(GoRouterState state) {
  final roomId = state.pathParameters['roomid'];
  return roomId == null ? null : fullRoomId(roomId);
}

/// The activity an open route addresses: the in-course overlay (`?activity=`)
/// or the standalone uuid route (`/:activityId`). Carries the optional session
/// `roomid` and `launch` flag that the canonical open uses.
({String id, String? roomId, bool launch})? activityFor(GoRouterState state) {
  final id =
      state.uri.queryParameters['activity'] ?? state.pathParameters['activityId'];
  if (id == null || id.isEmpty) return null;
  final roomId = state.uri.queryParameters['roomid'];
  return (
    id: id,
    roomId: roomId == null ? null : fullRoomId(roomId),
    launch: state.uri.queryParameters['launch'] == 'true',
  );
}

/// What the map should focus. Today: the open activity. Extend by adding a
/// [MapFocus] subclass and returning it here.
MapFocus? mapFocusFor(GoRouterState state) {
  final activity = activityFor(state);
  if (activity != null) return ActivityFocus(activity.id);
  return null;
}

/// Whether the left column (the section card over the map) is shown. World and
/// the add-course hub have no left column.
bool showLeftColumn(GoRouterState state) =>
    sectionFor(state.uri) != AppSection.world &&
    state.fullPath != _fullBleedRoute;

/// Whether the navigation rail (column mode) / bottom nav (narrow mode) shows.
/// In column mode it is always present; in narrow mode it is suppressed on
/// deep detail views (a room/space leaf, a construct drilldown).
bool showNavRail(GoRouterState state, bool isColumnMode) {
  if (isColumnMode) return true;
  final roomId = state.pathParameters['roomid'];
  final spaceId = state.pathParameters['spaceid'];
  if (roomId == null && spaceId == null) {
    // Construct drilldowns hide the bar; everything else keeps it.
    return !(state.fullPath?.contains(':construct') ?? false);
  }
  if (roomId == null) {
    // Only the bare course root keeps the bar among space subroutes.
    return state.fullPath?.endsWith(':spaceid') ?? false;
  }
  return false;
}

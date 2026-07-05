import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/activity_token.dart';
import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/features/navigation/panel_registry.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';

/// World_v2 routing facts — the single place navigation/layout decisions are
/// derived from a [GoRouterState]. Every consumer (the shell layout, the
/// left-column switcher, the nav rail, the bottom nav, the map) calls these
/// instead of re-deriving from path segments, so they cannot disagree.
///
/// See `routing.instructions.md` for the model and `deep-linking.instructions.md`
/// for the cross-repo contract.

/// How a route's canvas relates to the persistent world map. Two modes today:
/// the map shows through, or a bounded detail sits over it with the map peeking.
/// (There is no full-screen takeover — even an activity plan is a bounded detail
/// / a mobile sheet; see `routing.instructions.md`.)
enum CanvasMode {
  /// Paints nothing; the persistent map shows through (section roots).
  mapHole,

  /// Opaque panel capped at the detail width; the map peeks alongside.
  detail,
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

/// The learning-analytics metric the top-right cluster opens as a right-column
/// panel. Each maps to a `?right=analytics:<name>` token in the workspace URL
/// (the single source of truth for open panels). See `routing.instructions.md`.
enum AnalyticsPanelTab { sessions, grammar, vocab }

/// Whether [fullPath] renders as the map hole — the persistent world map shows
/// through with nothing drawn over it. world_v2: only the world root `/` is a
/// map hole now. Every section moved to a token panel rendered by the shell, so
/// its old path renders nothing (and the section paths redirect to tokens before
/// matching anyway). The shell reads this via [canvasFor].
bool isMapHole(String? fullPath) => fullPath == PRoutes.world;

/// The effective canvas for the current route's sideView. The world root `/` is a
/// map hole (sideView offstage, full map shows); everything reached by a real
/// route — a course-wizard step, a public-course preview, a chat archive — is a
/// bounded `detail` with the map peeking beside it. An open activity is **not** a
/// canvas exception anymore (#7385): it rides as a first-class `left=activity:`
/// panel over the map hole (sized by the allocator like a `room`, a bottom sheet
/// on narrow), not a floorless center detail. See `routing.instructions.md`.
CanvasMode canvasFor(GoRouterState state, bool isColumnMode) {
  if (isMapHole(state.fullPath)) return CanvasMode.mapHole;
  return CanvasMode.detail;
}

/// The active top-level section. `/rooms/...` belongs to chats; first-class
/// world-object uuids render over the map (world). Unknown → world (a sane
/// nav highlight); the canvas is decided by [canvasFor], not the section, so an
/// unrecognized detail route never flips the shell to the world map.
AppSection sectionFor(Uri uri) {
  // The rail highlight shows what you're looking at (routing.instructions.md
  // decision 5). Precedence:
  //  1. The global chat LIST wins — even with a live room beside it, and even
  //     under a lingering `?c=` context: switching to Chats un-highlights the
  //     course (the #7467 "quest stays selected" oddity).
  //  2. Any course surface → Courses: a course card / management page / the
  //     add-course hub, OR a `?c=` context in any form — a course room beside
  //     its card (`left=course,room`), a lone course room (card closed), an
  //     in-course activity, or the empty scoped-map backdrop. A course room
  //     reads as its course, not as the global chat list.
  //  3. Only a lone room with no course context is a direct chat → Chats.
  final left = parseOpenPanels(uri).left;
  if (left.any((t) => t.type == 'chats')) return AppSection.chats;
  if (left.any(
        (t) =>
            t.type == 'course' ||
            t.type == 'coursepage' ||
            t.type == 'addcourse',
      ) ||
      activeSpaceIdFor(uri) != null) {
    return AppSection.courses;
  }
  if (left.any((t) => t.type == 'room')) return AppSection.chats;
  // The few real route-driven paths (fork `/rooms/...` pages, the course
  // Completer flows and public preview) highlight by first segment.
  final first = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
  if (first == 'rooms') return AppSection.chats;
  if (first == 'courses') return AppSection.courses;
  return AppSection.world;
}

/// The active course space id — the workspace's `?c=<spaceid>` course context
/// (a bare localpart) — else null. One value read by the map (scope) and the
/// course-family panels (identity) alike, independent of the panel tokens.
/// Re-attaches the home server_name for callers that hit the Matrix client.
/// See `routing.instructions.md`.
String? activeSpaceIdFor(Uri uri) {
  for (final part in uri.query.split('&')) {
    if (part.startsWith('c=') && part.length > 2) {
      return fullRoomId(Uri.decodeComponent(part.substring(2)));
    }
  }
  return null;
}

/// The open room id from the world_v2 panel tokens (a `room:` token in the
/// `left=` / `right=` lists), or null. This is the chat the list highlights as
/// active (#7208).
String? activeRoomIdFromPanels(Uri uri) {
  final panels = parseOpenPanels(uri);
  for (final token in [...panels.left, ...panels.right]) {
    if (token.type == 'room' && token.param != null) {
      return fullRoomId(token.param!);
    }
  }
  return null;
}

/// The active chat/course room id, if the route addresses one — the legacy
/// `/rooms/:roomid` path param, or the world_v2 open `room:` panel token.
String? activeRoomIdFor(GoRouterState state) {
  final roomId = state.pathParameters['roomid'];
  if (roomId != null) return fullRoomId(roomId);
  return activeRoomIdFromPanels(state.uri);
}

/// The activity an open URI addresses: the `left=activity:` panel token,
/// whose structured param carries the id plus optional session bindings — the
/// bound room, launch, autoplay ([ActivityToken]).
({String id, String? roomId, bool launch, int? autoplay})? activityInfoFor(
  Uri uri,
) {
  for (final token in parseOpenPanels(uri).left) {
    if (token.type == 'activity' && (token.param?.isNotEmpty ?? false)) {
      return ActivityToken.parse(token.param!);
    }
  }
  return null;
}

/// [activityInfoFor] over a [GoRouterState]'s URI.
({String id, String? roomId, bool launch, int? autoplay})? activityFor(
  GoRouterState state,
) => activityInfoFor(state.uri);

/// What the map should focus. Today: the open activity. Extend by adding a
/// [MapFocus] subclass and returning it here.
MapFocus? mapFocusFor(GoRouterState state) {
  final activity = activityFor(state);
  if (activity != null) return ActivityFocus(activity.id);
  return null;
}

/// Whether the navigation rail (column mode) / bottom nav (narrow mode) shows.
/// In column mode it is always present; in narrow mode it is suppressed on
/// deep detail views (a room/space leaf, a construct drilldown).
bool showNavRail(GoRouterState state, bool isColumnMode) {
  if (isColumnMode) return true;
  // An in-progress activity is immersive: on a narrow screen the bottom nav is
  // suppressed so a stray tap (World/Chats/Avatar) can't abandon the activity
  // mid-task — the design marks an activity the exclusive surface, and it carries
  // its own exit. See `routing.instructions.md`.
  if (activityFor(state) != null) return false;
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

/// The maximum panels honored per URL list; extra tokens are dropped to guard a
/// hand-crafted or runaway URL. Tune against a realistic worst case.
const int _maxPanelsPerList = 6;

/// The open panels named by the workspace URL: the ordered `left=` and `right=`
/// lists. The URL is the single source of truth for which panels are open and
/// in what order. Unknown types, wrong-column tokens, and duplicate
/// (type, param) pairs are dropped, so a hand-edited URL degrades to a valid
/// subset rather than crashing — duplicate room ids would otherwise collide as
/// duplicate widget keys. See `routing.instructions.md`.
({List<PanelToken> left, List<PanelToken> right}) parseOpenPanels(Uri uri) =>
    (left: _parsePanelList(uri, 'left'), right: _parsePanelList(uri, 'right'));

/// Whether [token]'s navigation-tree parent (per the registry) is currently open
/// in either column. The close affordance reads this on a narrow single pane:
/// only the focused leaf is drawn, so closing it returns to its **parent** (`←`,
/// a genuine back-step) when that parent sits behind it, versus dismissing to the
/// bare map (`X`) when it is an independent panel whose parent is not open.
/// Reading the same parent tree the allocator's leaf rule uses keeps the
/// affordance and the focus consistent — a raw "is any other panel open" count
/// would wrongly show `←` over an unrelated panel and drop one-tap dismiss. The
/// parent may be in the other column (a left `session` over the right `analytics`
/// list). See `close_affordance.dart` / `panel_registry.dart`.
bool parentIsOpen(Uri uri, PanelToken token) {
  final parentType = PanelRegistry.defFor(token.type)?.parent;
  if (parentType == null) return false;
  final lists = parseOpenPanels(uri);
  return lists.left.any((t) => t.type == parentType) ||
      lists.right.any((t) => t.type == parentType);
}

List<PanelToken> _parsePanelList(Uri uri, String key) {
  // Read the raw query, not uri.queryParameters: the latter percent-decodes,
  // which would turn an encoded construct's %2C back into a delimiter comma and
  // shatter the token. Split the still-encoded value first, decode per token
  // (in PanelToken.parse). This deliberately diverges from every other consumer
  // here, which reads the decoded queryParameters — do not "fix" it back.
  final query = uri.query;
  if (query.isEmpty) return const [];
  String? encodedList;
  for (final part in query.split('&')) {
    if (part.startsWith('$key=')) {
      encodedList = part.substring(key.length + 1);
      break;
    }
  }
  if (encodedList == null || encodedList.isEmpty) return const [];

  final column = key == 'left' ? PanelColumn.left : PanelColumn.right;
  final seen = <String>{};
  final usedGroups = <String>{};
  final tokens = <PanelToken>[];
  // A plain comma split is safe: param content is field-encoded, so a literal
  // comma can never survive into the list (token_fields.dart).
  for (final element in encodedList.split(',')) {
    final token = PanelToken.parse(element);
    if (token == null) continue;
    final def = PanelRegistry.defFor(token.type);
    if (def == null || def.column != column) continue;
    // A `room`/`session` token's IDENTITY is its bare room id; the rest of the
    // param is a pushed sub-page (`<id>/search`, `<id>/details/…`). Dedup on the
    // bare id so a hand-edited URL with two sub-pages of the same room degrades
    // to one panel rather than colliding on the room's GlobalKey. Other panels
    // dedup on the whole (type, param). See `routing.instructions.md`.
    final identity = (token.type == 'room' || token.type == 'session')
        ? '${token.type}:${(token.param ?? '').split('/').first}'
        : '${token.type}:${token.param ?? ''}';
    if (!seen.add(identity)) continue;
    // Siblings can't coexist: at most one token per sibling group survives in a
    // column (first wins). Without this a hand-edited / deep-link URL could
    // render two panels the nav helpers would never open together — e.g.
    // right=vocab:x,grammar:y (both in the `detail` group), or room+session
    // (both `liveView`). See panel_registry.dart.
    if (def.siblingGroups.any(usedGroups.contains)) continue;
    usedGroups.addAll(def.siblingGroups);
    tokens.add(token);
    if (tokens.length >= _maxPanelsPerList) break;
  }
  // Practice takes over the analytics surface, so it never coexists with the
  // analytics master (the `detail` group already excludes vocab/grammar details).
  if (column == PanelColumn.right && tokens.any((t) => t.type == 'practice')) {
    tokens.removeWhere((t) => t.type == 'analytics');
  }
  // A `course` card and a `coursepage` management page read their space id from
  // the `?c=<id>` course context, not the token, so without it they have nothing
  // to render — a blank, close-less card a hand-edited or stale URL could strand
  // the user on (especially on a narrow single pane). Drop them when no course is
  // scoped. This is the only place a coursepage is shed for lost context:
  // closeSection keeps it (the context survives a card close), and
  // openCourseFilter sheds the previous course's page only because it re-targets
  // the context to a different course. See `routing.instructions.md`.
  if (column == PanelColumn.left && activeSpaceIdFor(uri) == null) {
    tokens.removeWhere((t) => t.type == 'course' || t.type == 'coursepage');
  }
  return _masterFirst(tokens);
}

/// Reorder a column's tokens so a registry master precedes its detail — the
/// canonical master-first order (routing.instructions.md). A shared link
/// written detail-first (an older spelling) normalizes here; a pair the
/// registry does not relate (a `course` card beside a live `room`, whose
/// parent is `chats`) keeps its given order. Lists are at most a few tokens.
List<PanelToken> _masterFirst(List<PanelToken> tokens) {
  final result = List<PanelToken>.from(tokens);
  for (var i = 0; i < result.length; i++) {
    final parentType = PanelRegistry.defFor(result[i].type)?.parent;
    if (parentType == null) continue;
    final parentIdx = result.indexWhere((t) => t.type == parentType);
    if (parentIdx > i) {
      // A detail precedes its master — move it to just after the master.
      final detail = result.removeAt(i);
      result.insert(result.indexWhere((t) => t.type == parentType) + 1, detail);
      i = -1; // restart; the list is tiny
    }
  }
  return result;
}

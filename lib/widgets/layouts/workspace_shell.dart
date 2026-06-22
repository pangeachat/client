import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/panel_focus.dart';
import 'package:fluffychat/features/navigation/panel_registry.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/routes/world/activity_detail_panel.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/panel_card.dart';
import 'package:fluffychat/routes/world/workspace_left_panel.dart';
import 'package:fluffychat/routes/world/workspace_right_panel.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/widgets/layouts/mobile_course_sheet.dart';
import 'package:fluffychat/widgets/layouts/panel_allocator.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mobile_bottom_nav.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:fluffychat/widgets/space_navigation_column.dart';

/// One persistent world-map element for the whole app shell (world_v2 map
/// architecture). The GlobalKey preserves the map's State — tiles, camera,
/// pins — even if this shell page is rebuilt or remounted across navigation,
/// so sections open *over* the map instead of refreshing it.
final GlobalKey _persistentWorldMapKey = GlobalKey(debugLabel: 'worldMap');

/// Preserves the top-right cluster's State (counts, level, stream subs) across
/// shell rebuilds, like the persistent map — so it does not re-fetch on nav.
final GlobalKey _userClusterKey = GlobalKey(debugLabel: 'worldUserCluster');

/// Per-room GlobalKeys for left-column chat panels, keyed by room id **only**
/// (never eventId, unlike `chat.dart`'s `ChatPageWithRoom` key). A live room's
/// `ChatController` — its timeline, choreographer, and subscriptions — survives
/// a slot *reposition* as the `?left=` list grows or shrinks (a sibling panel
/// opens/closes), because the shell reparents the same element rather than
/// remounting it. Keyed by room means navigating to a *different* room remounts
/// (correct: new timeline), while moving the *same* room repositions.
///
/// A `room` is a **child** in the navigation tree (the chat list's detail), and
/// the allocator only ever folds a **parent** behind its child — so a live room
/// is never folded out of the layout (its master, the chat list, folds first)
/// and, being the leaf, is the focus in single-column mode. The session
/// therefore survives every relayout, fold included. See `routing.instructions.md`.
final Map<String, GlobalKey> _leftRoomKeys = {};
GlobalKey _roomKeyFor(String roomId) => _leftRoomKeys.putIfAbsent(
  roomId,
  () => GlobalKey(debugLabel: 'leftRoom:$roomId'),
);

/// Narrow (single-pane) focus recency: the visible compact pane is the
/// most-recently-opened one (the back-stack top), per Material 3 / Flutter
/// adaptive guidance — NOT raw priority, which made opening a low-priority panel
/// over a live room a visible no-op. The allocator falls back to the navigation
/// tree's leaf rule when there is no recency (a cold link). Ephemeral view state,
/// deliberately OUTSIDE the URL: a width change must not reshuffle panes or add
/// history. Module-level so it survives shell rebuilds. Synced once per build by
/// [_ShellLayout.resolve]. See `routing.instructions.md`.
final List<String> _paneRecency = <String>[];

/// The world_v2 workspace shell: a single persistent [WorldMap] with the open
/// panels overlaid. Not "two columns" — it owns the map backdrop, the nav rail,
/// the top-right cluster, the center canvas/detail, AND both panel columns. Every
/// routing/layout fact comes from `route_facts.dart` (the single source).
/// Left- and right-column panels (the chat list, a room, a course; analytics, a
/// vocab/grammar detail, a completed-activity review) are named by the URL's
/// `?left=`/`?right=` lists and positioned by [PanelAllocator] — one shared
/// width budget so panels and the route-driven center detail tile without
/// overlap. See `routing.instructions.md`.
///
/// [build] is deliberately thin: it resolves every layout fact into one
/// immutable [_ShellLayout] bundle, schedules that frame's controller
/// side-effects, then assembles the [Stack] from the named `_…Layer` helpers
/// below — each of which reads only from the bundle. The dense derivation all
/// lives in [_ShellLayout.resolve].
class WorkspaceShell extends StatelessWidget {
  // #Pangea
  final GoRouterState state;
  // Pangea#
  final Widget sideView;

  const WorkspaceShell({
    super.key,
    // #Pangea
    required this.state,
    // Pangea#
    required this.sideView,
  });

  @override
  Widget build(BuildContext context) {
    final l = _ShellLayout.resolve(context, state: state, sideView: sideView);
    l.scheduleControllers();

    return ScaffoldMessenger(
      child: Scaffold(
        // At a section-root level the bottom nav shows — unless a map-pin preview
        // sheet is open over the map, which replaces it (the map owns that
        // selection, so a notifier carries the signal up here). See
        // `routing.instructions.md`.
        bottomNavigationBar: l.showBottomNav
            ? ValueListenableBuilder<bool>(
                valueListenable: MapPinController.notifier,
                builder: (context, pinSheetOpen, child) =>
                    pinSheetOpen ? const SizedBox.shrink() : child!,
                child: MobileBottomNav(state: state),
              )
            : null,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _mapLayer(l),
            _canvasLayer(l),
            if (l.mobileCourseIndex != null) _mobileCourseSheet(l),
            if (l.isMobileActivity) _mobileActivitySheet(l),
            _navRailLayer(l),
            ..._leftPanelLayers(l),
            ..._rightPanelLayers(l),
            if ((l.mapVisible && l.allocation.clusterVisible) ||
                l.isMobileCourse ||
                l.isMobileActivity)
              _clusterLayer(context),
          ],
        ),
      ),
    );
  }

  /// Persistent world map — the base layer everything overlays. Overlays pad the
  /// camera so a course fit lands in the exposed area: left = rail + column +
  /// detail; right = the panel zone.
  Widget _mapLayer(_ShellLayout l) => Positioned.fill(
    child: WorldMap(
      key: _persistentWorldMapKey,
      leftOverlayWidth: l.mapLeftOverlay,
      rightOverlayWidth: l.allocation.mapRightOverlay,
      focus: mapFocusFor(state),
    ),
  );

  /// The route canvas, as one stable child so the sideView Navigator never
  /// remounts when the canvas mode changes:
  ///  • mapHole → Offstage so pan/zoom/tap reach the map below.
  ///  • detail → capped, bounded by the right panel zone; map peeks (an activity
  ///    plan on a wide screen; a course-wizard step).
  Widget _canvasLayer(_ShellLayout l) => Positioned(
    left: l.leftInset,
    top: 0,
    bottom: 0,
    right: l.canvas == CanvasMode.detail ? null : 0,
    width: l.canvas == CanvasMode.detail ? l.detailWidth : null,
    child: Offstage(
      // A map hole shows the full map through; a narrow activity plan is
      // offstaged here too because its content rides in the bottom sheet below.
      // Otherwise the center detail (an activity plan on a wide screen, a
      // course-wizard step, a public-course preview) gets the same floating-card
      // chrome as the column panels via [PanelCard].
      offstage: l.canvas == CanvasMode.mapHole || l.isMobileActivity,
      child: l.canvas == CanvasMode.detail
          ? PanelCard(child: l.canvasChild)
          : l.canvasChild,
    ),
  );

  /// A narrow course rides in a draggable bottom sheet over the course-scoped
  /// map (Google-Maps "map + sheet"). The course content is the same
  /// WorkspaceLeftPanel surface, hosted [bare] (the sheet is the card). The
  /// left-panel loop skips this index so it is not also drawn full-screen. See
  /// `routing.instructions.md`.
  Widget _mobileCourseSheet(_ShellLayout l) => Positioned.fill(
    child: MobileCourseSheet(
      child: WorkspaceLeftPanel(
        token: l.leftTokens[l.mobileCourseIndex!],
        currentUri: state.uri,
        bare: true,
      ),
    ),
  );

  /// A narrow activity plan rides in the same bottom sheet over the map (camera
  /// on its pin); the center canvas is offstaged for it in [_canvasLayer].
  Widget _mobileActivitySheet(_ShellLayout l) =>
      Positioned.fill(child: MobileCourseSheet(child: l.canvasChild));

  /// The nav rail must size to its content, NOT fill the Stack: this Stack is
  /// StackFit.expand, which forces non-positioned children to full size — and the
  /// rail's root (opaque-canvas) Material would then paint over the entire
  /// persistent map below it (blank map; mobile was fine because the rail is
  /// `SizedBox.shrink` there). Align tops it left at its natural size so the map
  /// stays full-bleed behind it.
  Widget _navRailLayer(_ShellLayout l) => Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.all(_ShellLayout.chromeMargin),
      child: SpaceNavigationColumn(state: state, showNavRail: l.navRail),
    ),
  );

  /// Left-column panels (the chat list, a live room, a course, the
  /// settings/profile menu) from `?left=`, each at its allocator slot. The
  /// floating-card chrome AND margin live in [PanelCard] (inside
  /// WorkspaceLeftPanel), shared with the right column and the center detail.
  /// Keyed by token so opening/closing a sibling panel doesn't shift indices and
  /// remount this one; a `room` panel additionally carries a roomId GlobalKey so
  /// its ChatController repositions rather than remounts when the slot moves.
  List<Widget> _leftPanelLayers(_ShellLayout l) => [
    for (var i = 0; i < l.leftTokens.length; i++)
      // Skip a narrow course card — it renders in the bottom sheet above, not as
      // a full-screen left panel (no double-render).
      if (i != l.mobileCourseIndex &&
          l.allocation.left[i].vis != PanelVis.hidden)
        Positioned(
          key: ValueKey(l.leftTokens[i].encode()),
          top: 0,
          bottom: 0,
          left: l.allocation.left[i].left,
          width: l.allocation.left[i].width,
          child: _leftPanel(
            l.leftTokens[i],
            state.uri,
            l.allocation.left[i].foldedOver,
          ),
        ),
  ];

  /// Right-column panels (analytics summary, a vocab/grammar detail, a
  /// completed-activity review) from `?right=`, each placed at its allocator
  /// slot. The slots tile and never overlap by construction; a folded slot is
  /// `hidden` (not drawn), its content one back-step away on the higher-priority
  /// sibling that stayed.
  List<Widget> _rightPanelLayers(_ShellLayout l) => [
    for (var i = 0; i < l.rightTokens.length; i++)
      if (l.allocation.right[i].vis != PanelVis.hidden)
        Positioned(
          // Keyed by token so a left-column open/close (which shifts sibling
          // indices in this Stack) reconciles the right panel by identity, not
          // position — otherwise its stateful content (analytics, a detail) would
          // remount and re-fetch.
          key: ValueKey(l.rightTokens[i].encode()),
          top: 0,
          bottom: 0,
          left: l.allocation.right[i].left,
          width: l.allocation.right[i].width,
          child: WorkspaceRightPanel(
            token: l.rightTokens[i],
            currentUri: state.uri,
            foldedOver: l.allocation.right[i].foldedOver,
          ),
        ),
  ];

  /// The persistent top-right user cluster — the right column's entry point. It
  /// sits in the gutter the allocator reserves beside the panels; hidden behind a
  /// narrow full-screen panel. Shown over a narrow course or activity sheet too
  /// (the map is visible above the sheet, so the floating cluster reads as
  /// Maps-style chrome and keeps analytics reachable). The caller gates
  /// visibility; this only places it.
  Widget _clusterLayer(BuildContext context) => Positioned(
    top: _ShellLayout.chromeMargin + MediaQuery.viewPaddingOf(context).top,
    right: _ShellLayout.chromeMargin + MediaQuery.viewPaddingOf(context).right,
    child: WorldUserCluster(key: _userClusterKey),
  );

  /// Builds one left-column panel for [token]. A `room` panel is wrapped in a
  /// roomId-keyed [GlobalKey] so the same [ChatController] is reparented (not
  /// remounted) when its slot moves; other left surfaces are cheap to rebuild
  /// and key by position.
  Widget _leftPanel(PanelToken token, Uri uri, bool foldedOver) {
    // Forward any shared items (carried on the navigation `extra`, not the URL)
    // to a `room` token — the share sheet opens its target as the sole live
    // room, so the extra belongs to whichever room renders. See
    // `routing.instructions.md`.
    final shareItems = token.type == 'room' && state.extra is List<ShareItem>
        ? state.extra as List<ShareItem>
        : null;
    final panel = WorkspaceLeftPanel(
      token: token,
      currentUri: uri,
      foldedOver: foldedOver,
      shareItems: shareItems,
    );
    if (token.type == 'room') {
      // The room token's param is `<roomid>` or `<roomid>/<subpage>`; the
      // GlobalKey is keyed by the bare room id only, so pushing a sub-page
      // (search/details/…) repositions the same ChatController rather than
      // remounting it. See `routing.instructions.md`.
      final param = token.param ?? '';
      final slash = param.indexOf('/');
      final bareId = slash < 0 ? param : param.substring(0, slash);
      return KeyedSubtree(key: _roomKeyFor(fullRoomId(bareId)), child: panel);
    }
    return panel;
  }
}

/// Every layout fact the [WorkspaceShell] derives from the current route +
/// viewport, resolved once per build into one immutable bundle so `build` reads
/// each value by name instead of threading a wall of interdependent locals.
///
/// [resolve] is the single home for that derivation (moved verbatim from the old
/// inline `build`), including the build-time [_paneRecency] sync that picks the
/// narrow focus. [scheduleControllers] applies the per-frame side-effects that
/// must run AFTER the frame (publishing map context / panel focus / pin state to
/// their controllers). See `routing.instructions.md`.
@immutable
class _ShellLayout {
  /// One shared margin for every floating chrome edge (the rail pill and the
  /// top-right cluster), so they inset from the viewport identically.
  static const double chromeMargin = 12.0;

  /// Whether the nav rail shows (vertical-left in column mode, bottom bar narrow).
  final bool navRail;

  /// Left-/right-column panel tokens from the URL — the single source of truth
  /// for what's open. Parallel to [layout].left / [layout].right.
  final List<PanelToken> leftTokens;
  final List<PanelToken> rightTokens;

  /// The resolved panel placement (slots, cluster visibility, map camera
  /// padding) from [PanelAllocator].
  final WorkspaceLayout allocation;

  /// The effective center canvas (an open activity overlay already resolved to a
  /// detail panel inside [canvasFor]).
  final CanvasMode canvas;

  /// `?activity=<id>` opens the activity detail in-place over the map; this is
  /// the resolved canvas child (the activity panel, else the route [sideView]).
  final Widget canvasChild;

  /// Index into [leftTokens] of a narrow joined-course card that rides in the
  /// bottom sheet (null otherwise); [isMobileCourse] is its presence.
  final int? mobileCourseIndex;
  final bool isMobileCourse;

  /// A narrow activity plan rides in the bottom sheet over the map.
  final bool isMobileActivity;

  /// The narrow bottom nav (section switcher) shows only at a section-root level.
  final bool showBottomNav;

  /// The map shows behind as a map hole (full) or, in column mode, alongside a
  /// detail; this gates the cluster.
  final bool mapVisible;

  /// Where the left column ends — the center detail and the map's left camera
  /// padding both begin here so neither slides under a left panel.
  final double leftInset;

  /// The route-driven center detail width, bounded so it can never slide under a
  /// panel (null when there is no bounded center detail).
  final double? detailWidth;

  /// Map camera left padding (the left inset plus any center detail width).
  final double mapLeftOverlay;

  // Side-effect inputs, published post-frame by [scheduleControllers].
  final MapContext mapContext;
  final String? focusedLeftToken;
  final bool mapCoveredByPanel;

  const _ShellLayout({
    required this.navRail,
    required this.leftTokens,
    required this.rightTokens,
    required this.allocation,
    required this.canvas,
    required this.canvasChild,
    required this.mobileCourseIndex,
    required this.isMobileCourse,
    required this.isMobileActivity,
    required this.showBottomNav,
    required this.mapVisible,
    required this.leftInset,
    required this.detailWidth,
    required this.mapLeftOverlay,
    required this.mapContext,
    required this.focusedLeftToken,
    required this.mapCoveredByPanel,
  });

  factory _ShellLayout.resolve(
    BuildContext context, {
    required GoRouterState state,
    required Widget sideView,
  }) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final navRail = showNavRail(state, isColumnMode);

    // Left-column panels named by the URL's `?left=` list — the same token
    // model as the right column. Every section is token-driven now (the
    // route-driven `_MainView` left card was retired), so the left column is
    // entirely the allocator's; the only fixed left inset is the nav rail.
    final leftTokens = parseOpenPanels(state.uri).left;
    final leftDefs = [
      for (final token in leftTokens) PanelRegistry.defFor(token.type)!,
    ];
    final hasLeftTokens = leftTokens.isNotEmpty;

    // The single live left chat panel, if any — the focus signal a chat's
    // ChatController listens to instead of the router. By the one-live-view rule
    // a `room` and a `session` are mutually exclusive, so the first room-or-session
    // token is the live one; publish it (a `session` review is a real timeline
    // too, so it must be focusable exactly like a `room`). ChatController matches
    // by bare room id, so either token type focuses correctly. Published
    // post-frame in [scheduleControllers].
    String? focusedLeftToken;
    for (final token in leftTokens) {
      if (token.type == 'room' || token.type == 'session') {
        focusedLeftToken = token.encode();
        break;
      }
    }

    // world_v2: the rail is vertical-left in column mode and a bottom bar in
    // narrow mode, so it only offsets the canvas in column mode. The left inset
    // is just the rail now — there is no route-driven left card to reserve for.
    final railWidth = isColumnMode && navRail
        ? (FluffyThemes.navRailWidth + 1.0)
        : 0.0;
    // The rail floats over the map in its dock pill, inset by [chromeMargin] on
    // each side; reserve that margin so left panels and the camera padding clear
    // it.
    final columnWidth = railWidth == 0 ? 0.0 : railWidth + chromeMargin * 2;

    // The effective canvas (an open activity overlay already resolves to a
    // detail panel inside [canvasFor]).
    final canvas = canvasFor(state, isColumnMode);
    final activity = activityFor(state);
    final activeSpaceId = activeSpaceIdFor(state.uri);

    final viewport = MediaQuery.sizeOf(context).width;

    // Right-column panels from the URL — the single source of truth for what's
    // open. Every token parsed here has a valid right-column def (the parser
    // dropped unknown/wrong-column tokens), so the lookup is non-null.
    final rightTokens = parseOpenPanels(state.uri).right;
    final rightDefs = [
      for (final token in rightTokens) PanelRegistry.defFor(token.type)!,
    ];

    // Narrow focus = the most-recently-opened panel (back-stack top). Sync the
    // recency list against the open tokens: append newly-opened ids (in list
    // order), prune closed ones; the merged [left…, right…] id order matches the
    // allocator's entry order, so the focus index maps straight through. The sync
    // is idempotent for an unchanged token set, so a width change never
    // reshuffles panes or adds history. Ephemeral view state, deliberately OUTSIDE
    // the URL (a shared link / refresh has no recency and the allocator falls back
    // to the tree's leaf rule). Consulted in narrow mode (which pane to seat) and
    // in column mode (the just-opened pane is protected from a left↔right parity
    // collapse, #7088). See `routing.instructions.md`.
    final paneIds = [
      for (final t in leftTokens) t.encode(),
      for (final t in rightTokens) t.encode(),
    ];
    _paneRecency.removeWhere((id) => !paneIds.contains(id));
    for (final id in paneIds) {
      if (!_paneRecency.contains(id)) _paneRecency.add(id);
    }
    final focusHint = _paneRecency.isNotEmpty
        ? paneIds.indexOf(_paneRecency.last)
        : null;

    final layout = PanelAllocator.allocate(
      viewport: viewport,
      isColumnMode: isColumnMode,
      left: leftDefs,
      right: rightDefs,
      railWidth: columnWidth,
      focusHint: focusHint,
    );

    // world_v2 mobile: a joined COURSE on a narrow screen rides in a draggable
    // bottom sheet over the (course-scoped) map — the Google-Maps "map + sheet"
    // pattern — instead of a full-screen panel. Active when the focused narrow
    // panel is the `course` card (an in-course `room` or an activity shows itself
    // instead; switching course tabs still focuses the card). The course content
    // is hosted bare in the sheet, and the normal left-panel loop skips this index
    // so the course is not also drawn full-screen behind the sheet — the
    // double-render the old `canvas == detail` predicate (always false for a
    // course on `/`) never guarded. See `routing.instructions.md`.
    int? mobileCourseIndex;
    if (!isColumnMode && activity == null && activeSpaceId != null) {
      for (var i = 0; i < leftTokens.length; i++) {
        if (leftTokens[i].type == 'course' &&
            layout.left[i].vis == PanelVis.full) {
          mobileCourseIndex = i;
          break;
        }
      }
    }
    final isMobileCourse = mobileCourseIndex != null;

    // An activity's plan/preview is map content too: on a narrow screen it rides
    // in the same bottom sheet over the map (camera on the activity's pin), not a
    // full-screen page — the `?activity=` center canvas is offstaged and the sheet
    // hosts it. On a wide screen it stays a bounded center detail with the map
    // peeking beside it. See `routing.instructions.md`.
    final isMobileActivity = !isColumnMode && activity != null;

    // The narrow bottom nav is only the section switcher (World / Chats /
    // Courses), so it shows only at a "section-root" level: the bare map (no
    // focused panel), the chat list, or the courses list. Any focused DETAIL (a
    // chat, a settings/analytics/vocab page, a session) hides it — you back out
    // via the panel's own control — and a bottom SHEET (a course, or a tapped
    // pin) replaces it outright (the course case falls out here since `course`
    // isn't a section-root type; the pin case is handled by the MapPinController
    // listener on the bar). See `routing.instructions.md`.
    String? focusedNarrowType;
    if (!isColumnMode) {
      for (var i = 0; i < leftTokens.length; i++) {
        if (layout.left[i].vis == PanelVis.full) {
          focusedNarrowType = leftTokens[i].type;
          break;
        }
      }
      if (focusedNarrowType == null) {
        for (var i = 0; i < rightTokens.length; i++) {
          if (layout.right[i].vis == PanelVis.full) {
            focusedNarrowType = rightTokens[i].type;
            break;
          }
        }
      }
    }
    final atSectionRoot =
        focusedNarrowType == null ||
        focusedNarrowType == 'chats' ||
        focusedNarrowType == 'addcourse';
    final showBottomNav = !isColumnMode && navRail && atSectionRoot;

    // The map shows behind as a map hole (full) or — in column mode — alongside
    // a detail; this gates the cluster.
    final mapVisible =
        canvas == CanvasMode.mapHole ||
        (isColumnMode && canvas == CanvasMode.detail);

    // Where the left column ends. With `?left=` panels the allocator computes
    // it (the right edge of the last left panel, `leftCovered`); otherwise it's
    // the fixed chrome inset. The center detail tile and the map's left camera
    // padding both begin here so neither can slide under a left panel. Map
    // content on a narrow screen (a course card, an activity plan) rides in a
    // bottom sheet over the FULL map, not a left panel, so the camera uses the
    // whole width (the sheet covers the bottom, which the left/right overlays
    // don't model). See `routing.instructions.md`.
    final leftInset = (isMobileCourse || isMobileActivity)
        ? 0.0
        : (hasLeftTokens ? layout.mapLeftOverlay : columnWidth);

    // Bound the route-driven center detail by the left inset and the right-
    // covered width so it can never slide under a panel (the non-overlap
    // guarantee). A narrow activity plan is a bottom sheet, not a center detail,
    // so it claims no center width here (the sheet hosts it below).
    final detailWidth = canvas == CanvasMode.detail && !isMobileActivity
        ? math.min(
            PanelAllocator.detailMax,
            math.max(0.0, viewport - leftInset - layout.mapRightOverlay),
          )
        : null;
    final mapLeftOverlay = (isMobileCourse || isMobileActivity)
        ? 0.0
        : leftInset +
              (canvas == CanvasMode.detail ? (detailWidth ?? 0.0) : 0.0);

    // Scope the persistent map to the active course (world_v2 context). Set
    // post-frame — the map listens and calls setState, which can't run now.
    final coursePlanId = activeSpaceId == null
        ? null
        : Matrix.of(
            context,
          ).client.getRoomById(activeSpaceId)?.coursePlan?.uuid;
    final MapContext mapContext = coursePlanId == null
        ? const WorldMapContext()
        : CourseMapContext(coursePlanId);
    // A full-screen panel on a narrow screen covers the map, so dismiss any
    // lingering map-pin preview — otherwise its [MapPinController] flag would keep
    // the bottom nav hidden at a section root (chats / courses list). A course
    // SHEET leaves the map visible above it, so it does not clear the pin. The
    // map clears its own selection in response. See `routing.instructions.md`.
    final mapCoveredByPanel =
        !isColumnMode && focusedNarrowType != null && !isMobileCourse;

    // `?activity=<id>` opens the activity detail in-place over the map.
    final canvasChild = activity != null
        ? ActivityDetailPanel(
            activityId: activity.id,
            parentSpaceId: activeSpaceId,
            roomId: activity.roomId,
            launch: activity.launch,
          )
        : sideView;

    return _ShellLayout(
      navRail: navRail,
      leftTokens: leftTokens,
      rightTokens: rightTokens,
      allocation: layout,
      canvas: canvas,
      canvasChild: canvasChild,
      mobileCourseIndex: mobileCourseIndex,
      isMobileCourse: isMobileCourse,
      isMobileActivity: isMobileActivity,
      showBottomNav: showBottomNav,
      mapVisible: mapVisible,
      leftInset: leftInset,
      detailWidth: detailWidth,
      mapLeftOverlay: mapLeftOverlay,
      mapContext: mapContext,
      focusedLeftToken: focusedLeftToken,
      mapCoveredByPanel: mapCoveredByPanel,
    );
  }

  /// Publish this frame's map context, left-panel focus, and (when a narrow
  /// panel covers the map) the cleared pin preview to their controllers. Deferred
  /// to post-frame because each set() drives a listener `setState`, which can't
  /// run during this build.
  void scheduleControllers() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MapContextController.set(mapContext);
      PanelFocusController.instance.set(focusedLeftToken);
      if (mapCoveredByPanel) MapPinController.set(false);
    });
  }
}

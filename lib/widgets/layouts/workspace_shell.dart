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

/// The world_v2 workspace shell: a single persistent [WorldMap] with the open
/// panels overlaid. Not "two columns" — it owns the map backdrop, the nav rail,
/// the top-right cluster, the center canvas/detail, AND both panel columns. Every
/// routing/layout fact comes from `route_facts.dart` (the single source).
/// Left- and right-column panels (the chat list, a room, a course; analytics, a
/// vocab/grammar detail, a completed-activity review) are named by the URL's
/// `?left=`/`?right=` lists and positioned by [PanelAllocator] — one shared
/// width budget so panels and the route-driven center detail tile without
/// overlap. The narrow (single-pane) focus is the active **leaf** of the
/// navigation tree, computed by the allocator from the registry's parent links —
/// no shell-side recency state. See `routing.instructions.md`.
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

    // The single live room panel, if any — the focus signal a room's
    // ChatController listens to instead of the router (one-live-session rule, so
    // the first room token is the live one). Published post-frame below.
    String? focusedLeftToken;
    for (final token in leftTokens) {
      if (token.type == 'room') {
        focusedLeftToken = token.encode();
        break;
      }
    }

    // world_v2: the rail is vertical-left in column mode and a bottom bar in
    // narrow mode, so it only offsets the canvas in column mode. The left inset
    // is just the rail now — there is no route-driven left card to reserve for.
    final railWidth =
        isColumnMode && navRail ? (FluffyThemes.navRailWidth + 1.0) : 0.0;
    // One shared margin for every floating chrome edge (the rail pill and the
    // top-right cluster), so they inset from the viewport identically. The rail
    // floats over the map in its dock pill, inset by [chromeMargin] on each
    // side; reserve that margin so left panels and the camera padding clear it.
    const chromeMargin = 12.0;
    final columnWidth = railWidth == 0 ? 0.0 : railWidth + chromeMargin * 2;
    final showBottomNav = !isColumnMode && navRail;

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

    final layout = PanelAllocator.allocate(
      viewport: viewport,
      isColumnMode: isColumnMode,
      left: leftDefs,
      right: rightDefs,
      railWidth: columnWidth,
    );

    // The map shows behind as a map hole (full) or — in column mode — alongside
    // a detail; this gates the cluster.
    final mapVisible =
        canvas == CanvasMode.mapHole ||
        (isColumnMode && canvas == CanvasMode.detail);

    // Where the left column ends. With `?left=` panels the allocator computes
    // it (the right edge of the last left panel, `leftCovered`); otherwise it's
    // the fixed chrome inset. The center detail tile and the map's left camera
    // padding both begin here so neither can slide under a left panel.
    final leftInset = hasLeftTokens ? layout.mapLeftOverlay : columnWidth;

    // Bound the route-driven center detail by the left inset and the right-
    // covered width so it can never slide under a panel (the non-overlap
    // guarantee).
    final detailWidth = canvas == CanvasMode.detail
        ? math.min(
            PanelAllocator.detailMax,
            math.max(0.0, viewport - leftInset - layout.mapRightOverlay),
          )
        : null;
    final mapLeftOverlay =
        leftInset + (canvas == CanvasMode.detail ? (detailWidth ?? 0.0) : 0.0);

    // Scope the persistent map to the active course (world_v2 context). Set
    // post-frame — the map listens and calls setState, which can't run now.
    final coursePlanId = activeSpaceId == null
        ? null
        : Matrix.of(context).client.getRoomById(activeSpaceId)?.coursePlan?.uuid;
    final MapContext mapContext = coursePlanId == null
        ? const WorldMapContext()
        : CourseMapContext(coursePlanId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MapContextController.set(mapContext);
      PanelFocusController.instance.set(focusedLeftToken);
    });

    // world_v2 mobile: a joined course on a narrow screen rides in a draggable
    // bottom sheet over the persistent (course-scoped) map.
    final isMobileCourse =
        !isColumnMode &&
        activeSpaceId != null &&
        activity == null &&
        canvas == CanvasMode.detail;

    // `?activity=<id>` opens the activity detail in-place over the map.
    final canvasChild = activity != null
        ? ActivityDetailPanel(
            activityId: activity.id,
            parentSpaceId: activeSpaceId,
            roomId: activity.roomId,
            launch: activity.launch,
          )
        : sideView;

    return ScaffoldMessenger(
      child: Scaffold(
        bottomNavigationBar: showBottomNav
            ? MobileBottomNav(state: state)
            : null,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Persistent world map — the base layer everything overlays.
            Positioned.fill(
              child: WorldMap(
                key: _persistentWorldMapKey,
                // Overlays pad the camera so a course fit lands in the exposed
                // area: left = rail + column + detail; right = the panel zone.
                leftOverlayWidth: mapLeftOverlay,
                rightOverlayWidth: layout.mapRightOverlay,
                focus: mapFocusFor(state),
              ),
            ),
            // The route canvas, as one stable child so the sideView Navigator
            // never remounts when the canvas mode changes:
            //  • mapHole → Offstage so pan/zoom/tap reach the map below.
            //  • detail → capped, bounded by the right panel zone; map peeks.
            //  • fullBleed → fills (the activity page hosts its own map).
            Positioned(
              left: leftInset,
              top: 0,
              bottom: 0,
              right: canvas == CanvasMode.detail ? null : 0,
              width: canvas == CanvasMode.detail ? detailWidth : null,
              child: Offstage(
                offstage: canvas == CanvasMode.mapHole || isMobileCourse,
                // The center detail (an activity, a course-wizard step, a
                // public-course preview) gets the SAME floating-card chrome as
                // the column panels — rounded, elevated, same margin — via the
                // shared [PanelCard]. A full-bleed canvas fills bare.
                child: isMobileCourse
                    ? const SizedBox.shrink()
                    : canvas == CanvasMode.detail
                        ? PanelCard(child: canvasChild)
                        : canvasChild,
              ),
            ),
            if (isMobileCourse)
              Positioned.fill(child: MobileCourseSheet(child: canvasChild)),
            // The rail must size to its content, NOT fill the Stack: this Stack
            // is StackFit.expand, which forces non-positioned children to full
            // size — and the rail's root (opaque-canvas) Material would then
            // paint over the entire persistent map below it (blank map; mobile
            // was fine because the rail is `SizedBox.shrink` there). Align tops
            // it left at its natural size so the map stays full-bleed behind it.
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(chromeMargin),
                child:
                    SpaceNavigationColumn(state: state, showNavRail: navRail),
              ),
            ),
            // Left-column panels (the chat list, a live room, a course, the
            // settings/profile menu) from `?left=`, each at its allocator slot.
            // The floating-card chrome AND margin live in [PanelCard] (inside
            // WorkspaceLeftPanel), shared with the right column and the center
            // detail. Keyed by token so opening/closing a sibling panel doesn't
            // shift indices and remount this one; a `room` panel additionally
            // carries a roomId GlobalKey so its ChatController repositions rather
            // than remounts when the slot moves.
            for (var i = 0; i < leftTokens.length; i++)
              if (layout.left[i].vis != PanelVis.hidden)
                Positioned(
                  key: ValueKey(leftTokens[i].encode()),
                  top: 0,
                  bottom: 0,
                  left: layout.left[i].left,
                  width: layout.left[i].width,
                  child: _leftPanel(
                    leftTokens[i],
                    state.uri,
                    layout.left[i].foldedOver,
                  ),
                ),
            // Right-column panels (analytics summary, a vocab/grammar detail, a
            // completed-activity review) from `?right=`, each placed at its
            // allocator slot. The slots tile and never overlap by construction;
            // a folded slot is `hidden` (not drawn), its content one back-step
            // away on the higher-priority sibling that stayed.
            for (var i = 0; i < rightTokens.length; i++)
              if (layout.right[i].vis != PanelVis.hidden)
                Positioned(
                  // Keyed by token so a left-column open/close (which shifts
                  // sibling indices in this Stack) reconciles the right panel by
                  // identity, not position — otherwise its stateful content
                  // (analytics, a detail) would remount and re-fetch.
                  key: ValueKey(rightTokens[i].encode()),
                  top: 0,
                  bottom: 0,
                  left: layout.right[i].left,
                  width: layout.right[i].width,
                  child: WorkspaceRightPanel(
                    token: rightTokens[i],
                    currentUri: state.uri,
                    foldedOver: layout.right[i].foldedOver,
                  ),
                ),
            // The persistent top-right user cluster — the right column's entry
            // point. It sits in the gutter the allocator reserves beside the
            // panels; hidden on a full-bleed canvas or behind a narrow panel.
            if (mapVisible && layout.clusterVisible)
              Positioned(
                top: chromeMargin + MediaQuery.viewPaddingOf(context).top,
                right: chromeMargin + MediaQuery.viewPaddingOf(context).right,
                child: WorldUserCluster(key: _userClusterKey),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds one left-column panel for [token]. A `room` panel is wrapped in a
  /// roomId-keyed [GlobalKey] so the same [ChatController] is reparented (not
  /// remounted) when its slot moves; other left surfaces are cheap to rebuild
  /// and key by position.
  Widget _leftPanel(PanelToken token, Uri uri, bool foldedOver) {
    // Forward any shared items (carried on the navigation `extra`, not the URL)
    // to a `room` token — the share sheet opens its target as the sole live
    // room, so the extra belongs to whichever room renders. See
    // `routing.instructions.md`.
    final shareItems =
        token.type == 'room' && state.extra is List<ShareItem>
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
      return KeyedSubtree(
        key: _roomKeyFor(fullRoomId(bareId)),
        child: panel,
      );
    }
    return panel;
  }
}

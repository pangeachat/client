import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:badges/badges.dart' show BadgePosition;
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/dm_invite/dm_invite_ferry_consumer.dart';
import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/features/navigation/panel_focus.dart';
import 'package:fluffychat/features/navigation/panel_registry.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/course_avatar.dart';
import 'package:fluffychat/pangea/common/widgets/invited_course_badge.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/pangea/spaces/knocking_users_badge.dart';
import 'package:fluffychat/pangea/spaces/knocking_users_builder.dart';
import 'package:fluffychat/routes/world/left_panel/workspace_left_panel.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/mobile_search_bar.dart';
import 'package:fluffychat/routes/world/right_panel/workspace_right_panel.dart';
import 'package:fluffychat/routes/world/world_analytics_bar.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/routes/world/world_map_mobile_filters.dart';
import 'package:fluffychat/routes/world/world_map_pins_manager.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/layouts/left_panel_layer.dart';
import 'package:fluffychat/widgets/layouts/mobile_nav_widget.dart';
import 'package:fluffychat/widgets/layouts/navigation_extras_extension.dart';
import 'package:fluffychat/widgets/layouts/panel_allocator.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/navigation_rail.dart';
import 'package:fluffychat/widgets/unread_rooms_badge.dart';

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

/// The stable recency identity of an open panel — its *family instance*, not its
/// current page. Navigating WITHIN a panel changes the token string but must NOT
/// change which panel is the recency focus (a within-panel move is a push on the
/// panel's own stack, not a fresh open; see `routing.instructions.md`), so the
/// key deliberately ignores the parts of the token that a within-panel
/// navigation rewrites:
///
///  - The family is the **root of the navigation tree** ([PanelDef.parent]
///    chain): a `settingspage` detail keys as its `settings` master, a
///    `vocab`/`grammar` construct as its `analytics` summary, a `coursepage` as
///    its `course` card — so opening/paging a detail off a master keeps the
///    master's recency slot instead of demoting an unrelated open popup.
///  - The instance is the family root's **identity**: a `room`/`session` is
///    keyed by its bare room id (the `<id>/subpage` push is stripped, mirroring
///    the URL parser's dedup), so two different rooms stay distinct while a
///    room → members push keeps one slot. A singleton family (settings,
///    analytics, course — whose live identity is the `?m=` filter, not the tab
///    param) keys on the root type alone, so a tab/page switch reuses its slot.
///
/// This is the one fix point for #7104 ("open tabs switching places"): the
/// allocator's Tier-2 collapse and narrow-mode focus both read the recency-derived
/// `focusHint`, so keying recency on stable identity stops a within-panel
/// navigation from stealing focus and evicting the other column's popup.
String _recencyKey(PanelToken token) {
  // Walk to the navigation-tree root so a detail inherits its master's slot.
  var def = token.type.def;
  var rootType = token.type;
  // Bounded by the registry depth (two generations today); guard against a
  // malformed cyclic/self parent just in case.
  final seen = <PanelTypesEnum>{rootType};
  while (def.parent != null && seen.add(def.parent!)) {
    rootType = def.parent!;
    def = rootType.def;
  }
  // A room/session instance is its bare room id; the rest is a pushed sub-page.
  // A `room` keeps its OWN type as the root (its parent `chats` is the list, a
  // separate panel), so this branch is reached with the original type.
  final type = token.type;
  final param = token.param;
  if (type.isRoomPanel && param is RoomTokenParam) {
    return '${type.name}:${param.id}';
  }
  // Every other family (settings/analytics/course/chats/addcourse/practice/
  // review) is a singleton per column: key on the root type, so paging or
  // tab-switching within it reuses the one slot.
  return rootType.name;
}

/// Whether the narrow rail's 4th slot — the course shortcut — is showing the
/// surface the cavity currently hosts, which makes its tap the
/// tap-the-active-item TOGGLE rather than a navigation
/// (routing.instructions.md → "Collapsing is not closing").
///
/// The slot resolves contextually, so "its own surface" does too:
///
/// - **A joined course** ([shortcutCourseId] non-null) — the shortcut is that
///   course's avatar, and its surface is that course's card: hosted exactly
///   when the cavity is a course panel under that course's context (#7537).
/// - **No joined courses** — the shortcut is the `+` add-course button, so its
///   surface is the add-course hub the Courses rail item ALSO opens. Without
///   this arm the shortcut re-issued a same-URL `setSection(addcourse)` — a
///   silent no-op — so the button neither opened nor closed the hub once it
///   was up, while the Courses item beside it toggled fine (#8098).
///
/// Pure so it is unit-tested directly, away from the shell's Matrix lookups.
@visibleForTesting
bool courseShortcutHostsCavity({
  required PanelToken? cavityToken,
  required String? shortcutCourseId,
  required String? activeSpaceId,
}) {
  if (cavityToken == null) return false;
  if (shortcutCourseId == null) {
    // The `+` slot: its surface is the add-course family, which is exactly what
    // `cavitySection` reports as the Courses rail item's own surface.
    return cavityToken.type.cavitySection == AppSection.courses;
  }
  return cavityToken.type.isCoursePanel && shortcutCourseId == activeSpaceId;
}

/// Sync the back-stack [recency] against the currently open [allTokens] (merged
/// `[left…, right…]`, the allocator's entry order) and return the allocator
/// `focusHint` index, or null when nothing is open.
///
/// Recency is keyed on STABLE panel identity ([_recencyKey]) — the panel-family
/// instance, not the per-page token string — so navigating WITHIN a panel (a
/// settings menu → page, a room → members, a course tab switch, a vocab detail
/// off the analytics summary) reuses the panel's existing slot instead of
/// jumping to most-recent. Without this, navigating inside one popup stole the
/// back-stack top from an unrelated open popup, and the column-mode Tier-2
/// collapse then evicted that OTHER popup — so the two appeared to swap columns
/// (#7104). A genuinely new panel (a different room, the first detail of a
/// family) still mints a new key and is promoted as the user expects.
///
/// The recency-top key can match more than one open pane (a master and its
/// detail share a key, e.g. `course` + `coursepage`, `settings` + `settingspage`);
/// resolve to the **leaf** — the pane no other open pane names as parent — so the
/// just-opened detail wins focus over its master regardless of list order (a left
/// detail appends after its master; a right detail front-inserts). This mirrors
/// the allocator's own leaf rule. Mutates [recency] in place. Pure and
/// allocator-free so it is unit-tested directly. See `routing.instructions.md`.
@visibleForTesting
int? recencyFocusHint(List<PanelToken> allTokens, List<String> recency) {
  final paneKeys = [for (final t in allTokens) _recencyKey(t)];
  recency.removeWhere((id) => !paneKeys.contains(id));
  for (final id in paneKeys) {
    if (!recency.contains(id)) recency.add(id);
  }
  if (recency.isEmpty) return null;
  final topKey = recency.last;
  final matches = <int>[
    for (var i = 0; i < paneKeys.length; i++)
      if (paneKeys[i] == topKey) i,
  ];
  if (matches.isEmpty) return null;
  return matches.firstWhere(
    (i) => !allTokens.any((t) => t.type.def.parent == allTokens[i].type),
    orElse: () => matches.last,
  );
}

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

    return Semantics(
      label: L10n.of(context).home,
      child: ScaffoldMessenger(
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Scaffold(
            // No bottomNavigationBar slot: the narrow chrome is the FLOATING nav
            // widget (rail + expandable cavity) stacked over the map below, so it
            // can grow upward and let the map show through around it. See
            // `routing.instructions.md` → Single-column bottom nav.
            // The persistent WorldMap stays full-bleed (edge to edge, behind the
            // status bar) as the base layer — routing.instructions.md. Only the
            // foreground chrome/panels sit inside the SafeArea below.
            body: Stack(
              fit: StackFit.expand,
              children: [
                /// Persistent world map — the base layer everything overlays. Overlays pad the
                /// camera so a course fit lands in the exposed area: left = rail + column +
                /// detail; right = the panel zone.
                WorldMap(
                  key: _persistentWorldMapKey,
                  leftOverlayWidth: l.mapLeftOverlay,
                  rightOverlayWidth: l.allocation.mapRightOverlay,
                  bottomOverlayHeight: l.mapBottomOverlay,
                  availableVisibleMapWidth: l.availableVisibleMapWidth,
                  focus: mapFocusFor(state),
                ),

                /// Headless: opens a DM invite link's DM once the shell is up
                /// (the invite route only caches + lands here — the map, not a
                /// blank page, is what a slow first sync shows). Zero-size; it
                /// is a shell resident so it exists exactly when logged in.
                DmInviteFerryConsumer(uri: state.uri),

                // Everything above the map respects the device safe area; the
                // map itself does not (it is full-bleed, see above).
                Positioned.fill(
                  child: SafeArea(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        /// The route canvas, as one stable child
                        Positioned(
                          left: l.leftInset,
                          top: 0,
                          bottom: 0,
                          right: 0,
                          width: null,
                          child: Offstage(child: l.canvasChild),
                        ),

                        /// The narrow floating nav widget: the 4-item rail with the
                        /// expandable cavity above it hosting the focused section surface
                        /// (the chat list, the Courses hub, a course card) bare — the widget
                        /// is the card. Hidden while a map-pin preview sheet is open (the
                        /// map owns that selection; the notifier carries the signal up), and
                        /// entirely absent under a focused full-screen surface. See
                        /// `routing.instructions.md` → Single-column bottom nav.
                        if (l.navWidgetVisible)
                          ValueListenableBuilder<bool>(
                            valueListenable: WorldMapPinsManager.notifier,
                            builder: (context, pinSheetOpen, child) =>
                                pinSheetOpen ? const SizedBox.shrink() : child!,
                            child: _MobileNavLayer(
                              state: state,
                              layout: l,
                              screenPadding: MediaQuery.viewPaddingOf(context),
                              // Only the keyboard's overlap BEYOND the bottom safe
                              // area (home indicator) should trim the cavity: once
                              // the keyboard covers that strip, the SafeArea stops
                              // reserving it and the bottom-anchored nav layer
                              // already drops by that much. Trimming by the raw
                              // inset would double-count it and settle the cavity
                              // top ~34pt low. Read above the Scaffold, where
                              // `viewInsets` is still intact (#7754).
                              keyboardInset:
                                  (MediaQuery.viewInsetsOf(context).bottom -
                                          MediaQuery.viewPaddingOf(
                                            context,
                                          ).bottom)
                                      .clamp(0.0, double.infinity),
                            ),
                          ),

                        /// The nav rail must size to its content, NOT fill the Stack: this Stack is
                        /// StackFit.expand, which forces non-positioned children to full size — and the
                        /// rail's root (opaque-canvas) Material would then paint over the entire
                        /// persistent map below it (blank map; mobile was fine because the rail is
                        /// `SizedBox.shrink` there). Align tops it left at its natural size so the map
                        /// stays full-bleed behind it.
                        Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(
                              _ShellLayout.chromeMargin,
                            ),
                            child: SpacesNavigationRail(
                              state: state,
                              showNavRail: l.navRail,
                              naviRailWidth: FluffyThemes.navRailWidth + 1.0,
                              activeSpaceId: activeSpaceIdFor(state.uri),
                            ),
                          ),
                        ),

                        /// Left-column panels (the chat list, a live room, a course, the
                        /// settings/profile menu) from `?left=`, each at its allocator slot. The
                        /// floating-card chrome AND margin live in [PanelCard] (inside
                        /// WorkspaceLeftPanel), shared with the right column and the center detail.
                        /// Keyed by token so opening/closing a sibling panel doesn't shift indices and
                        /// remount this one; a `room` panel additionally carries a roomId GlobalKey so
                        /// its ChatController repositions rather than remounts when the slot moves.
                        ...[
                          for (var i = 0; i < l.leftTokens.length; i++)
                            // Skip the cavity-hosted surface (the chat list, the Courses
                            // hub, a course card) — it renders inside the nav widget's
                            // cavity, not as a full-screen left panel (no double-render).
                            if (i != l.cavityIndex &&
                                l.allocation.left[i].vis != PanelVis.hidden)
                              Positioned(
                                key: ValueKey(l.leftTokens[i].encode()),
                                // The narrow full-screen focus (a live room / session) is
                                // FULL-BLEED: no card chrome, edge to edge, top 0 — its own
                                // app bar absorbs the status-bar inset, and skipping the
                                // shell's extra safe-area offset removes the doubled top
                                // padding (#7554). Column-mode / non-focused panels keep
                                // the card and respect the top inset so their close/back
                                // control clears the system top bar (#7143); PanelCard's
                                // 12px top margin aligns them with the top-right cluster.
                                top: 0,
                                bottom: 0,
                                left: l.allocation.left[i].left,
                                width: l.allocation.left[i].width,
                                child: LeftPanelLayer(
                                  token: l.leftTokens[i],
                                  state: state,
                                  foldedOver: l.allocation.left[i].foldedOver,
                                  getRoomKey: _roomKeyFor,
                                  bare:
                                      !l.isColumnMode &&
                                      l.allocation.left[i].vis == PanelVis.full,
                                ),
                              ),
                        ],

                        /// Right-column panels (analytics summary, a vocab/grammar detail, a
                        /// completed-activity review) from `?right=`, each placed at its allocator
                        /// slot. The slots tile and never overlap by construction; a folded slot is
                        /// `hidden` (not drawn), its content one back-step away on the higher-priority
                        /// sibling that stayed.
                        ...[
                          for (var i = 0; i < l.rightTokens.length; i++)
                            if (l.allocation.right[i].vis != PanelVis.hidden)
                              Positioned(
                                // Keyed by token so a left-column open/close (which shifts sibling
                                // indices in this Stack) reconciles the right panel by identity, not
                                // position — otherwise its stateful content (analytics, a detail) would
                                // remount and re-fetch.
                                key: ValueKey(l.rightTokens[i].encode()),
                                // Respect the top safe-area inset so the close/back control clears the
                                // system top bar (#7143). On narrow the analytics bar heads the panel
                                // ("the analytics bar itself remains visible at the top throughout" —
                                // routing.instructions.md), so the panel starts below it.
                                top: l.isColumnMode
                                    ? 0
                                    : _ShellLayout.analyticsBarAllowance,
                                bottom: 0,
                                left: l.allocation.right[i].left,
                                width: l.allocation.right[i].width,
                                child: FocusTraversalGroup(
                                  policy: OrderedTraversalPolicy(),
                                  child: WorkspaceRightPanel(
                                    token: l.rightTokens[i],
                                    currentUri: state.uri,
                                    foldedOver:
                                        l.allocation.right[i].foldedOver,
                                  ),
                                ),
                              ),
                        ],

                        /// The right column's entry point. In column mode: the persistent
                        /// top-right vertical cluster, in the gutter the allocator reserves.
                        /// On narrow: the horizontal ANALYTICS NAV BAR pinned to the top
                        /// safe area — full form only, on the surfaces where it IS
                        /// navigation (the map/cavity ground and the right panels it
                        /// heads). A full-screen chat hosts the avatar in its own app bar
                        /// instead, and a route-driven detail page shows nothing. See
                        /// `routing.instructions.md` → Single-column analytics nav bar.
                        if (l.isColumnMode && l.allocation.clusterVisible)
                          Positioned(
                            top: _ShellLayout.chromeMargin,
                            right: _ShellLayout.chromeMargin,
                            child: WorldUserCluster(key: _userClusterKey),
                          )
                        else if (l.analyticsBarVisible)
                          Positioned(
                            top: _ShellLayout.chromeMargin,
                            left: _ShellLayout.chromeMargin,
                            right: _ShellLayout.chromeMargin,
                            // Fades out while the activity plan sits at full,
                            // where the sheet grows over this band. Kept mounted
                            // (opacity, not swapped out) so the bar holds its
                            // state — counts, stream subs — across the toggle.
                            child: ValueListenableBuilder<bool>(
                              valueListenable: ActivitySheetFull.notifier,
                              builder: (context, activityFull, child) =>
                                  IgnorePointer(
                                    ignoring: activityFull,
                                    child: AnimatedOpacity(
                                      opacity: activityFull ? 0.0 : 1.0,
                                      duration: FluffyThemes.animationDuration,
                                      child: child,
                                    ),
                                  ),
                              child: WorldAnalyticsBar(key: _userClusterKey),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The narrow floating nav widget layer: resolves the course-shortcut slot and
/// the cavity wiring from the current route, then mounts [MobileNavWidget]
/// with the floating search bar riding its `topAttachment` slot. Kept as its
/// own widget so the shell's `build` stays thin and the Matrix lookups
/// (joined courses, display names) run only when the layer shows.
class _MobileNavLayer extends StatefulWidget {
  final GoRouterState state;
  final _ShellLayout layout;
  final EdgeInsets screenPadding;

  /// Keyboard height, read above the Scaffold and forwarded to
  /// [MobileNavWidget] (see its `keyboardInset`). #7754.
  final double keyboardInset;
  const _MobileNavLayer({
    required this.state,
    required this.layout,
    required this.screenPadding,
    required this.keyboardInset,
  });

  @override
  State<_MobileNavLayer> createState() => _MobileNavLayerState();
}

class _MobileNavLayerState extends State<_MobileNavLayer> {
  /// Fit-height estimate inputs for the chats sheet: the cavity handle + the
  /// panel header row, and one two-line ChatListItem per visible chat.
  static const double _chatsSheetHeaderAllowance = 96.0;
  static const double _chatsSheetRowEstimate = 76.0;

  /// Fit-height estimate inputs for the Courses hub sheet: one course tile per
  /// joined course, or — when the learner is in no courses yet — the full
  /// add-course buttons block (the empty state). Reuses the shared cavity
  /// header allowance above.
  static const double _coursesSheetRowEstimate = 84.0;
  static const double _coursesSheetAddOptionsAllowance = 236.0;

  /// One Invited / Teaching / Learning section header row, when the hub
  /// groups by role (#8425): the row's text + 4px padding + the 8px separator.
  static const double _coursesSheetSectionHeaderEstimate = 36.0;

  /// The activity plan's minimized rest height: the cavity handle + the start
  /// page's app bar, info row, and CTA row, with no media/description. This is
  /// the plan's opening stop (there is no taller mid-level); dragging up goes
  /// to full, dragging down dismisses. Kept in step with
  /// `kActivityCompactMaxHeight` in activity_sessions_start_view.dart, which
  /// tells the body to drop its content below this height. See
  /// activity-start-page.instructions.md.
  static const double _activitySheetMinimizedHeight = 200.0;

  GoRouterState get state => widget.state;
  _ShellLayout get layout => widget.layout;

  /// The learner tapped the minimized search icon back open over a
  /// course-scoped map. Ephemeral view state; re-minimizes when the scope
  /// changes (routing.instructions.md → Single-column search bar).
  bool _searchRestored = false;
  String? _lastScopeId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final uri = state.uri;
    final screenHeight = MediaQuery.sizeOf(context).height;

    // The course-shortcut slot (routing.instructions.md): `+` when no courses
    // are joined, the single course when one, the most-recently-opened course
    // otherwise. The most-recent choice is device-local view state, never URL.
    final joined = client.rooms
        .where((r) => r.isSpace && r.membership == Membership.join)
        .toList();
    final activeSpaceId = activeSpaceIdFor(uri);
    if (activeSpaceId != null &&
        joined.any((space) => space.id == activeSpaceId)) {
      _lastCourseShortcutId = activeSpaceId;
    }
    final Room? shortcutCourse = joined.isEmpty
        ? null
        : joined.length == 1
        ? joined.first
        : joined.firstWhere(
            (space) => space.id == _lastCourseShortcutId,
            orElse: () => joined.first,
          );

    // The cavity: the focused section surface hosted bare (the widget is the
    // card; the surface brings its own header/close). A course keys its height
    // memory by the space id (#7332), an activity by its own id; the sections
    // key by name so their memory is their own.
    final cavityToken = layout.cavityIndex == null
        ? null
        : layout.leftTokens[layout.cavityIndex!];
    final isCourseCavity = cavityToken?.type.isCoursePanel == true;
    final isActivityCavity = cavityToken?.type == PanelTypesEnum.activity;
    final cavitySection = cavityToken?.type.cavitySection;

    // The floating search bar (routing.instructions.md → Single-column search
    // bar), riding the widget's topAttachment slot. It drives the map's own
    // filter (reached through the persistent map's State) in BOTH scopes — a
    // course scope narrows which activities compete, not whether the learner
    // can search within them (#7716). There is no narrow results list — the
    // pins ARE the results. The verdict-driven empty-view card and the
    // collapsible filter surface mount ABOVE the bar, since the bar sits at the
    // bottom on narrow layouts.
    final mapController =
        _persistentWorldMapKey.currentState as WorldMapController?;
    // Not over a selected activity or an open section sheet: the bar only rides
    // the exposed map band, which those cover (#7640). Over a bare COURSE-scoped
    // map it shows minimized — the compact icon, restorable by tap and
    // re-minimizing when the scope changes.
    if (_lastScopeId != activeSpaceId) {
      _lastScopeId = activeSpaceId;
      _searchRestored = false;
    }
    final showsSearchBar = cavityToken == null;
    final searchBar = showsSearchBar && mapController != null
        ? MobileSearchBar(
            hintText: l10n.mapSearchHint,
            query: mapController.filter.query,
            onQueryChanged: mapController.setQuery,
            minimized: activeSpaceId != null && !_searchRestored,
            onRestore: () => setState(() => _searchRestored = true),
            // The verdict-driven empty-view card (the web overlay's twin):
            // when the view shows no matches, the controller diagnoses WHY
            // (off-screen matches / pill-excluded matches / a dead query) and
            // the card offers the matching remedy. Builders read the map live
            // on each bar rebuild; the viewRevision tick triggers those
            // rebuilds for changes that don't originate in the bar (a pill
            // tap, a pin load after zooming out).
            emptyVerdict: () => mapController.emptyVerdict,
            canZoomOut: () => mapController.canZoomOut,
            onWidenSearch: mapController.widenFilters,
            // Resets to the whole-world view (all the way out, centered over
            // the fullest window of matching pins, #8121) — the map's World
            // control — so one tap reveals the most matches a floor-zoomed
            // narrow viewport can show, not just the next zoom level.
            onZoomOut: mapController.resetToWorld,
            viewRevision: mapController.viewRevision,
            // The collapsible filter surface riding above the bar — the narrow
            // twin of the wide overlay's [WorldMapFilterBar], wired to the same
            // controller callbacks. Reads the filter live (the shell is not
            // rebuilt by the map's setState) and collapses on a map pan.
            filtersChild: WorldMapMobileFilters(
              filterBuilder: () => mapController.filter,
              onSetLevel: mapController.setCefrLevel,
              onSetPartySize: mapController.setPartySize,
              onSetStatus: mapController.setStatus,
              onReset: mapController.resetFilters,
              collapseSignal: mapController.mapPanTick,
              filterRevision: mapController.viewRevision,
            ),
          )
        : null;

    // Full height: the widget grows until whatever rides above it sits
    // immediately below the analytics bar (routing.instructions.md).
    // [MobileNavWidget.maxHeightFraction] caps the CAVITY only — the rail row
    // and any search bar stack around it inside the same box — so the
    // reservation must count everything else in the vertical chain explicitly:
    // top safe area + analytics bar (margin + real height) + the search-bar
    // allowance ONLY when a search bar actually rides the widget + rail row +
    // bottom margin + bottom safe area + one margin of breathing room below
    // the bar. Omitting the rail row here previously let a fully-expanded
    // widget push the search bar under the analytics bar.
    final reserved = _ShellLayout.navChromeReserved(
      screenPadding: widget.screenPadding,
      hasSearchBar: searchBar != null,
      // The activity plan has no rail and covers the analytics bar at full, so
      // its full-height bound extends through both bands.
      reserveAnalyticsBar: !isActivityCavity,
      reserveRail: !isActivityCavity,
    );
    final maxHeightFraction = screenHeight <= 0
        ? 0.8
        : ((screenHeight - reserved) / screenHeight).clamp(0.3, 0.95);

    // The chats sheet opens showing ALL its chats when they fit: header +
    // one row per visible chat, capped by maxHeightFraction (the height below
    // the analytics bar). Row height is an estimate (a two-line ChatListItem);
    // a slight overshoot only adds breathing room, and the cap absorbs long
    // lists. Uses the same visibility predicate as the list's all-chats
    // filter so the estimate counts what actually renders.
    double? preferredCavityHeight;
    if (isActivityCavity) {
      preferredCavityHeight = _activitySheetMinimizedHeight;
    } else if (cavityToken?.type == PanelTypesEnum.chats) {
      final visibleChats = Matrix.of(context).client.rooms
          .where((room) => !room.isHiddenRoom && !room.isSpace)
          .length;
      preferredCavityHeight =
          _chatsSheetHeaderAllowance + visibleChats * _chatsSheetRowEstimate;
    } else if (cavityToken?.type == PanelTypesEnum.addcourse &&
        cavityToken?.param is! AddCoursePageTokenParam) {
      // The Courses hub opens tall enough to show all joined courses (or the
      // add-course buttons when there are none), capped by maxHeightFraction —
      // no longer defaulting to half (#7692). Same joined-course predicate as
      // the hub list, so the estimate counts exactly what renders.
      //
      // Content-fit is the HUB's rule only. Its subpages (browse public
      // courses, start my own, enter a code) show unrelated content that
      // arrives asynchronously, so a height derived from the joined-course
      // count leaves their lists too short to build a single row — browse then
      // reads as "no courses" until the learner drags the sheet up (#7542).
      // They fall through to the default (roughly half the screen), which is
      // what routing.instructions.md specifies for sections other than the
      // chats sheet and the Courses hub.
      final groups = client.coursesByRole(l10n);
      preferredCavityHeight =
          _chatsSheetHeaderAllowance +
          (groups.courseCount == 0
              ? _coursesSheetAddOptionsAllowance
              : groups.courseCount * _coursesSheetRowEstimate +
                    groups.sectionCount * _coursesSheetSectionHeaderEstimate);
    }

    String? cavityKey;
    if (cavityToken != null) {
      final param = cavityToken.param;
      if (isCourseCavity) {
        cavityKey = activeSpaceId ?? cavityToken.type.name;
      } else if (isActivityCavity) {
        cavityKey = param is ActivityTokenParam
            ? param.activityId
            : cavityToken.type.name;
      } else {
        cavityKey = cavityToken.type.name;
      }
    }

    // Positioned.fill, NOT a bottom-anchored strip: the widget bottom-aligns
    // its own box, and its tap-outside barrier must span the whole screen so a
    // map tap collapses the cavity (live QA — a bottom-anchored mount clipped
    // the barrier to the widget's own bounds).
    return Positioned.fill(
      child: MobileNavWidget(
        activeSection: sectionFor(uri),
        courseShortcutIcon: shortcutCourse != null
            // The same knock badge the web rail's course avatar wears: the
            // builder loads the member list (admins only) and rebuilds on
            // member changes, so the red "!" appears while users are knocking
            // and clears when the admin accepts/denies (#8139).
            ? KnockingUsersBuilder(
                room: shortcutCourse,
                builder: (context, knockingUsers) {
                  final avatar = CourseAvatar(
                    avatar: shortcutCourse.avatar,
                    displayname: shortcutCourse.getLocalizedDisplayname(
                      MatrixLocals(l10n),
                    ),
                    size: 32,
                  );
                  return knockingUsers.isEmpty
                      ? avatar
                      : KnockingUsersBadge(
                          position: BadgePosition.topEnd(top: -5, end: -7),
                          child: avatar,
                        );
                },
              )
            : const Icon(Icons.add),
        courseShortcutLabel: shortcutCourse != null
            ? shortcutCourse.getLocalizedDisplayname(MatrixLocals(l10n))
            : l10n.addCourse,
        courseShortcutSelected:
            shortcutCourse != null && shortcutCourse.id == activeSpaceId,
        // Rail navigations clear the right list: on one column a section and
        // a right panel are peers in the same slot, so opening a section must
        // close an open analytics/settings panel instead of leaving it stale
        // behind the sheet (routing.instructions.md → Single-column bottom
        // nav; the mirror of the analytics bar's closeSections).
        onCourseShortcutTap: () => context.go(
          shortcutCourse != null
              // No section param even for a knock-badged course: knocks
              // surface in the Catch up card at the top of the page (#8357),
              // which a scroll-to-Chats would skip right past.
              ? WorkspaceNav.openCourseSection(
                  uri,
                  shortcutCourse.id,
                  keepRoom: false,
                  clearRight: true,
                )
              : WorkspaceNav.setSection(
                  uri,
                  const AddCoursePanelToken(),
                  keepRoom: false,
                  clearRight: true,
                ),
        ),
        // The same all-chats unread badge the web rail's Chats item wears
        // (navigation_rail.dart): identical top-level-chats filter, identical
        // sync-driven rebuild — so the two tabs can't disagree (#8129).
        chatsBadgeBuilder: (child) => StreamBuilder(
          stream: client.onSync.stream
              .where((s) => s.hasRoomUpdate)
              .rateLimit(const Duration(seconds: 1)),
          builder: (context, _) => UnreadRoomsBadge(
            filter: (room) => room.firstSpaceParent == null,
            // Sits at the icon's corner with the web rail's proportions: the
            // rail badge covers ~30% of its 41px icon, so over this 24px icon
            // the badge must ride further up-and-out — at (4,4) it covered
            // half the glyph and read as touching it. The badge Stack is
            // Clip.none and the rail row leaves 8px above the 48px button, so
            // the small negative overhang stays fully visible.
            badgePosition: BadgePosition.topEnd(top: -1, end: -1),
            child: child,
          ),
        ),
        // The same gold envelope the invited course's own avatar wears in the
        // hub list, on the tab that opens it: a pending invitation is
        // otherwise invisible until the learner opens the Courses hub (#8190).
        // Same invited-space predicate as `sortedCourses`, so the badge shows
        // exactly when the hub has an invited course to show.
        coursesBadgeBuilder: (child) => StreamBuilder(
          stream: client.onSync.stream
              .where((s) => s.hasRoomUpdate)
              .rateLimit(const Duration(seconds: 1)),
          builder: (context, _) =>
              client.rooms.any(
                (r) => r.isSpace && r.membership == Membership.invite,
              )
              ? InvitedCourseBadge(
                  // The unread badge's position on the sibling Chats tab —
                  // both ride the corner of a 24px rail icon.
                  position: BadgePosition.topEnd(top: -1, end: -1),
                  child: child,
                )
              : child,
        ),
        onSectionTap: (section) => context.go(switch (section) {
          // World is home: clear every panel and reveal the full map.
          AppSection.world => WorkspaceNav.clearAll(),
          AppSection.chats => WorkspaceNav.setSection(
            uri,
            const ChatsPanelToken(),
            keepRoom: false,
            clearRight: true,
          ),
          AppSection.courses => WorkspaceNav.setSection(
            uri,
            const AddCoursePanelToken(),
            keepRoom: false,
            clearRight: true,
          ),
        }),
        cavitySection: cavitySection,
        // The shortcut hosts the cavity when it is showing that surface: the
        // shortcut's own course sheet, or — with no courses joined, where the
        // slot is the `+` button — the add-course hub (#8098).
        courseShortcutHostsCavity: courseShortcutHostsCavity(
          cavityToken: cavityToken,
          shortcutCourseId: shortcutCourse?.id,
          activeSpaceId: activeSpaceId,
        ),
        cavityChild: cavityToken == null
            ? null
            : FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: WorkspaceLeftPanel(
                  token: cavityToken,
                  currentUri: uri,
                  bare: true,
                  shareItems: state.navigatorShareItems(cavityToken),
                  courseCreationCompleter: state.navigatorCourseCompleter(
                    cavityToken,
                  ),
                ),
              ),
        cavityKey: cavityKey,
        // The course scope (`?c=`): a course's height is remembered while this
        // holds its id and forgotten when it leaves (World / a different
        // course). Opening a chat or activity from the course keeps it, so the
        // course reopens where it was left (#7332).
        cavityContextId: activeSpaceId,
        // A course card opens at peek (the map leads); sections and the
        // activity plan open at half (the plan keeps its pin visible above —
        // the Google Maps UX).
        cavityDefaultsToPeek: cavityToken?.type.defaultCavityToPeek == true,
        // Dismissing the activity plan sheet (drag down, or its own back/X)
        // CLOSES the plan — dropping its token clears the map's activity
        // focus (#7614; world-map.instructions.md). Map taps do NOT dismiss:
        // the map stays live around the sheet (mapStaysLive below), so a tap
        // on another pin moves the selection directly. Sections and the
        // course card keep collapse-not-close.
        onDismissed: isActivityCavity && cavityToken != null
            ? () => context.go(WorkspaceNav.closeLeft(uri, cavityToken))
            : null,
        // The map stays interactive around the activity plan and course card
        // sheets: taps/pans in the exposed map pass through — tap another pin
        // to select it directly; panning never dismisses. Dismissal is the
        // drag-down handle or the sheet's own close control (#7742).
        mapStaysLive: isActivityCavity || isCourseCavity,
        // Tapping the plan's minimized rest expands it to full, alongside
        // dragging up.
        tapBodyExpands: isActivityCavity,
        // The activity plan covers the nav rail and owns the container; its
        // app-bar X/back is the way out (which restores the rail).
        hideRail: isActivityCavity,
        // Publish whether the activity plan is at full — the shell hides the
        // analytics bar under it. Any other cavity reports false, so
        // switching away resets it.
        onCavityFullChanged: (full) =>
            ActivitySheetFull.set(value: isActivityCavity && full),
        maxHeightFraction: maxHeightFraction,
        preferredCavityHeightPx: preferredCavityHeight,
        // The activity plan's open stop is deterministic: it never remembers a
        // manual resize, so a maximized activity reopens minimized rather than
        // carrying its height over (activity-start-page.instructions.md). Other
        // cavities keep their remembered height.
        rememberHeight: !isActivityCavity,
        topAttachment: searchBar,
        keyboardInset: widget.keyboardInset,
      ),
    );
  }
}

/// Device-local memory of the last course the learner opened, for the narrow
/// rail's course-shortcut slot. Ephemeral view state, deliberately outside the
/// URL (routing.instructions.md → Single-column bottom nav). Module-level so it
/// survives shell rebuilds; resets with the process.
String? _lastCourseShortcutId;

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

  /// Height reserved for the narrow analytics bar when placing content below
  /// it: the bar's top margin ([chromeMargin]) plus its real rendered height
  /// ([WorldAnalyticsBar.expandedHeight]). Derived, not guessed — an earlier
  /// hand-picked 64 under-measured the 90px bar, so right panels' close
  /// controls rendered under the avatar column.
  static const double analyticsBarAllowance =
      chromeMargin + WorldAnalyticsBar.expandedHeight;

  /// Height reserved for the floating search bar riding above the nav widget —
  /// the widget's full-height bound stops the SEARCH BAR just below the
  /// analytics bar (routing.instructions.md → Single-column search bar).
  static const double searchBarAllowance = 56.0;

  /// The vertical chain around the nav widget's CAVITY that its full-height
  /// bound must reserve: top safe area + analytics bar + the search-bar
  /// allowance when one rides the widget + the rail row + bottom margin +
  /// bottom safe area + one margin of breathing room below the bar. Shared by
  /// the nav layer's [MobileNavWidget.maxHeightFraction] and the map's
  /// bottom camera padding ([mapBottomOverlay]) so the two can't drift.
  static double navChromeReserved({
    required EdgeInsets screenPadding,
    required bool hasSearchBar,
    // Set false to leave a band out of the reservation, letting the cavity's
    // full height extend through it: the activity plan has no rail and covers
    // the analytics bar at full.
    bool reserveAnalyticsBar = true,
    bool reserveRail = true,
  }) =>
      screenPadding.top +
      (reserveAnalyticsBar ? analyticsBarAllowance : 0.0) +
      (hasSearchBar ? searchBarAllowance : 0.0) +
      (reserveRail ? MobileNavWidget.railRowHeight : 0.0) +
      screenPadding.bottom +
      chromeMargin * 2;

  /// Whether the nav rail shows (vertical-left in column mode, bottom bar narrow).
  final bool navRail;

  /// Left-/right-column panel tokens from the URL — the single source of truth
  /// for what's open. Parallel to [layout].left / [layout].right.
  final List<PanelToken> leftTokens;
  final List<PanelToken> rightTokens;

  /// The resolved panel placement (slots, cluster visibility, map camera
  /// padding) from [PanelAllocator].
  final WorkspaceLayout allocation;

  /// The route [sideView]. The activity plan is no
  /// longer rendered here — it is a left panel hosted by [WorkspaceLeftPanel].
  final Widget canvasChild;

  /// Index into [leftTokens] of the panel hosted in the nav widget's expandable
  /// **cavity** on a narrow screen — the chat list, the Courses/add-course hub,
  /// the course family (card + coursepage detail), or the activity plan (a
  /// half-open sheet with the camera on its pin — the Google Maps UX). Null
  /// when nothing cavity-hosted is the narrow focus; [hasCavity] is its
  /// presence. Full-screen surfaces (a room, a session, any right panel) never
  /// ride the cavity. See `routing.instructions.md` → Single-column bottom nav.
  final int? cavityIndex;
  final bool hasCavity;

  /// The floating nav widget (rail + cavity) shows whenever the narrow chrome
  /// does, EXCEPT under a focused full-screen surface — which covers it. This
  /// replaces the old "bottom nav only at a section root" rule: the rail is now
  /// present (collapsed at minimum) wherever the map or a cavity is the ground.
  final bool navWidgetVisible;

  /// Whether the narrow analytics NAV BAR mounts (always in full form): over
  /// the map, a cavity, and an open right panel (the bar heads the panel).
  /// Absent on full-screen chats (the chat's app bar hosts
  /// [AnalyticsHeaderAvatar] instead) and on route-driven detail pages
  /// (nothing — they carry their own navigation). See
  /// `routing.instructions.md` → Single-column analytics nav bar.
  final bool analyticsBarVisible;

  /// Whether this layout resolved in two-column mode (chrome picks the web rail
  /// + cluster) or narrow mode (the mobile nav widget + analytics bar).
  final bool isColumnMode;

  /// Where the left column ends — the center detail and the map's left camera
  /// padding both begin here so neither slides under a left panel.
  final double leftInset;

  /// Map camera left padding (the left inset plus any center detail width).
  final double mapLeftOverlay;

  /// Map camera bottom padding: the vertical band the narrow activity-plan
  /// sheet occupies at its half-rest state, so a focused pin centers in the
  /// exposed map above the sheet (#7640). 0 everywhere else.
  final double mapBottomOverlay;

  /// The map actually visible between the open side panels (viewport − left
  /// overlay − right overlay) — drives the pin-density budget
  /// ([budgetForWidth] in world_map_pin_budget.dart).
  final double availableVisibleMapWidth;

  // Side-effect inputs, published post-frame by [scheduleControllers].
  final MapContext mapContext;
  final String? focusedLeftToken;
  final bool mapCoveredByPanel;

  const _ShellLayout({
    required this.navRail,
    required this.leftTokens,
    required this.rightTokens,
    required this.allocation,
    required this.canvasChild,
    required this.cavityIndex,
    required this.hasCavity,
    required this.navWidgetVisible,
    required this.analyticsBarVisible,
    required this.isColumnMode,
    required this.leftInset,
    required this.mapLeftOverlay,
    required this.mapBottomOverlay,
    required this.availableVisibleMapWidth,
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
    final leftDefs = [for (final token in leftTokens) token.type.def];
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
      if (token.type.isRoomPanel) {
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

    final activeSpaceId = activeSpaceIdFor(state.uri);

    final viewport = MediaQuery.sizeOf(context).width;

    // Right-column panels from the URL — the single source of truth for what's
    // open. Every token parsed here has a valid right-column def (the parser
    // dropped unknown/wrong-column tokens), so the lookup is non-null.
    final rightTokens = parseOpenPanels(state.uri).right;
    final rightDefs = [for (final token in rightTokens) token.type.def];

    // Narrow focus = the most-recently-opened panel (back-stack top). Sync the
    // recency list against the open panels: append newly-opened keys (in list
    // order), prune closed ones; the merged [left…, right…] order matches the
    // allocator's entry order, so the focus index maps straight through. The sync
    // is idempotent for an unchanged panel set, so a width change never
    // reshuffles panes or adds history. Ephemeral view state, deliberately OUTSIDE
    // the URL (a shared link / refresh has no recency and the allocator falls back
    // to the tree's leaf rule). Consulted in narrow mode (which pane to seat) and
    // in column mode (the just-opened pane is protected from a left↔right parity
    // collapse, #7088). See `routing.instructions.md`.
    //
    // The whole rule — STABLE-identity keying ([_recencyKey]) plus leaf
    // resolution of the recency-top key — lives in [recencyFocusHint], extracted
    // so it is unit-tested against real allocator input (#7104). It mutates
    // [_paneRecency] in place (the shared back-stack) and returns the focus index.
    final focusHint = recencyFocusHint([
      ...leftTokens,
      ...rightTokens,
    ], _paneRecency);

    final layout = PanelAllocator.allocate(
      viewport: viewport,
      isColumnMode: isColumnMode,
      left: leftDefs,
      right: rightDefs,
      railWidth: columnWidth,
      focusHint: focusHint,
    );

    // The narrow focus: the one panel the allocator seats full-screen, if any.
    // [focusedIsRight] distinguishes a right panel (renders under the expanded
    // analytics bar) from a left full-screen surface (collapses the bar).
    PanelTypesEnum? focusedNarrowType;
    var focusedIsRight = false;
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
            focusedIsRight = true;
            break;
          }
        }
      }
    }

    int? cavityIndex;
    if (!isColumnMode && focusedNarrowType != null && !focusedIsRight) {
      for (var i = 0; i < leftTokens.length; i++) {
        if (leftTokens[i].type.isCavity &&
            layout.left[i].vis == PanelVis.full) {
          cavityIndex = i;
          break;
        }
      }
    }
    final hasCavity = cavityIndex != null;

    // The floating nav widget shows wherever the narrow chrome does — the bare
    // map or a cavity surface (which includes the activity plan's half-open
    // sheet, #7530) — and is covered by a focused full-screen surface (a
    // room/session, a center-detail page, or a right panel expanding over it).
    final navWidgetVisible =
        !isColumnMode && navRail && (focusedNarrowType == null || hasCavity);

    // The analytics NAV BAR mounts only where it is navigation: over the map,
    // a cavity (including the activity plan's sheet), and an open right panel
    // (which it heads). A full-screen LEFT surface (a chat, a launched
    // session) hosts the header avatar in its own app bar instead, and a
    // center-detail page shows nothing — no floating chrome stacked over page
    // content.
    final analyticsBarVisible =
        !isColumnMode &&
        navRail &&
        (focusedNarrowType == null || hasCavity || focusedIsRight);

    // Where the left column ends. With `?left=` panels the allocator computes
    // it (the right edge of the last left panel, `leftCovered`); otherwise it's
    // the fixed chrome inset. The center detail tile and the map's left camera
    // padding both begin here so neither can slide under a left panel. Map
    // content on a narrow screen (a course card, an activity plan) rides in a
    // bottom sheet over the FULL map, not a left panel, so the camera uses the
    // whole width; the band the sheet covers is modeled separately as
    // [mapBottomOverlay]. See `routing.instructions.md`.
    final leftInset = hasCavity
        ? 0.0
        : (hasLeftTokens ? layout.mapLeftOverlay : columnWidth);

    final mapLeftOverlay = leftInset;

    // The narrow activity-plan sheet covers the bottom of the full-width map —
    // the band the left/right overlays don't model. Pad the camera's bottom by
    // the sheet's minimized rest (the height it opens at) so a focused pin
    // lands in the exposed map ABOVE the sheet instead of behind it (#7640;
    // activities doc — "the plan keeps its pin visible above", the Google Maps
    // target UX). The band is the minimized cavity height plus the bottom safe
    // area and a margin of breathing room; the sheet carries no rail. An
    // estimate of the resting sheet, deliberately not live-tracked: dragging
    // the sheet (or maximizing it) must not yank the camera.
    var mapBottomOverlay = 0.0;
    if (hasCavity && leftTokens[cavityIndex].type == PanelTypesEnum.activity) {
      mapBottomOverlay =
          _MobileNavLayerState._activitySheetMinimizedHeight +
          MediaQuery.viewPaddingOf(context).bottom +
          chromeMargin * 2;
    }

    // The map actually visible between the open side panels — drives the pin
    // density budget (world_map_pin_budget). A mobile sheet leaves the map
    // full-width (both overlays are 0). Clamped ≥ 0 for tiny viewports.
    final availableVisibleMapWidth = math.max(
      0.0,
      viewport - mapLeftOverlay - layout.mapRightOverlay,
    );

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
    // A full-screen surface on a narrow screen (a focused panel or a
    // center-detail page) covers the map, so dismiss any lingering map-pin
    // preview — otherwise its [MapPinController] flag would keep the nav
    // widget hidden after backing out. A CAVITY surface leaves the map visible
    // above it, so it does not clear the pin. The map clears its own selection
    // in response. See `routing.instructions.md`.
    final mapCoveredByPanel =
        !isColumnMode && (focusedNarrowType != null && !hasCavity);

    // Route-driven center detail only (a course-wizard step, a public-course
    // preview, a chat archive). The activity plan is a left panel now, not a canvas
    // child (#7385).
    final canvasChild = sideView;

    return _ShellLayout(
      navRail: navRail,
      leftTokens: leftTokens,
      rightTokens: rightTokens,
      allocation: layout,
      canvasChild: canvasChild,
      cavityIndex: cavityIndex,
      hasCavity: hasCavity,
      navWidgetVisible: navWidgetVisible,
      analyticsBarVisible: analyticsBarVisible,
      isColumnMode: isColumnMode,
      leftInset: leftInset,
      mapLeftOverlay: mapLeftOverlay,
      mapBottomOverlay: mapBottomOverlay,
      availableVisibleMapWidth: availableVisibleMapWidth,
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
      if (mapCoveredByPanel) WorldMapPinsManager.set(false);
    });
  }
}

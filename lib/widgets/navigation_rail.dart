import 'package:flutter/material.dart';

import 'package:badges/badges.dart' as b;
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/features/course_plans/map_clipper.dart';
import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/home/pangea_logo_svg.dart';
import 'package:fluffychat/routes/world/workspace_dock.dart';
import 'package:fluffychat/utils/chat_list_handle_space_tap.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/navi_rail_item.dart';

class SpacesNavigationRail extends StatelessWidget {
  final GoRouterState state;
  final String? activeSpaceId;
  final double naviRailWidth;
  final bool showNavRail;

  const SpacesNavigationRail({
    required this.state,
    required this.activeSpaceId,
    required this.naviRailWidth,
    required this.showNavRail,
    super.key,
  });

  Future<void> _onTapSpace(BuildContext context, String roomId) async {
    final uri = GoRouterState.of(context).uri;
    final client = Matrix.of(context).client;
    final room = client.getRoomById(roomId);
    final membership = room?.membership;

    if (!{Membership.invite, Membership.leave}.contains(membership)) {
      context.go(
        // A left-nav click replaces the open left panels rather than stacking
        // beside them (drop any open room/section). See routing.instructions.md.
        WorkspaceNav.openCourseSection(uri, roomId, keepRoom: false),
      );
      return;
    }

    final joinResp = room?.membership == Membership.invite
        ? await SpaceTapUtil.onInviteTap(context, room!)
        : await SpaceTapUtil.autoJoin(context, room!);

    if (joinResp == null) return;
    final joinedRoom = client.getRoomById(joinResp.roomId);
    if (joinedRoom == null) return;

    final handler = JoinRoomAnalyticsConsentHandler(joinResp, joinedRoom);
    final joinedRoomId = await handler.handle(context);
    if (joinedRoomId == null) return;

    context.go(
      WorkspaceNav.openCourseSection(uri, joinedRoomId, keepRoom: false),
    );
    return;
  }

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);

    // The vertical rail is column-mode only; narrow screens use the bottom nav.
    if (!isColumnMode || !showNavRail) return const SizedBox.shrink();

    final client = Matrix.of(context).client;

    // world_v2: section + active space from route_facts (the single resolver),
    // using the shell's state so the rail can't disagree with the shell.
    final section = sectionFor(state.uri);
    final isChats = section == AppSection.chats;
    final isWorld = section == AppSection.world;

    // The Add-course / find-course flow: courses section, no active space.
    final isCourseFind = section == AppSection.courses && activeSpaceId == null;

    final largeIconWidth = naviRailWidth - (isColumnMode ? 32.0 : 24.0);
    final smallIconWidth = naviRailWidth - (isColumnMode ? 40.0 : 32.0);

    // world_v2: the rail floats over the persistent map in the shared dock pill
    // (rounded, surface, elevated, outline-bordered) — the same chrome as the
    // top-right cluster, one source of truth. See workspace_dock.dart.
    return SafeArea(
      child: Padding(
        // Leave space for attributions widget to be visible
        padding: .only(bottom: 100),
        child: WorkspaceDock(
          child: Semantics(
            label: L10n.of(context).navOptionsLabel,
            container: true,
            child: StreamBuilder(
              key: ValueKey(client.userID.toString()),
              stream: client.onSync.stream
                  .where((s) => s.hasRoomUpdate)
                  .rateLimit(const Duration(seconds: 1)),
              builder: (context, _) {
                final allSpaces = client.rooms
                    .where((room) => room.isSpace)
                    .toList();

                return AnimatedContainer(
                  width: naviRailWidth,
                  duration: FluffyThemes.animationDuration,
                  // world_v2 rail order (top→bottom): World · Chats · Courses ·
                  // joined spaces. (Profile/settings is no longer a rail slot;
                  // analytics opens from the top-right cluster.)
                  child: Column(
                    // Size the rail to its items — a floating bar over the map, not
                    // the full screen height; it still scrolls if the joined-spaces
                    // list overflows the viewport.
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          scrollDirection: Axis.vertical,
                          children: [
                            // 1. World map home — the Pangea brand mark, at the top
                            // of the rail. Chromeless and avatar-sized; the left
                            // indicator bar conveys selection. Brand purple when
                            // active, muted when not.
                            NaviRailItem(
                              isSelected: isWorld,
                              backgroundColor: Colors.transparent,
                              // Exclude the logo's semanticsLabel so VoiceOver reads
                              // only the button tooltip ("world"), not the logo name.
                              icon: ExcludeSemantics(
                                child: PangeaLogoSvg(
                                  width: largeIconWidth,
                                  forceColor: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              selectedIcon: ExcludeSemantics(
                                child: PangeaLogoSvg(
                                  width: largeIconWidth,
                                  forceColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                ),
                              ),
                              onTap: () {
                                // World is home: clear every panel (both columns)
                                // and reveal the full map. See routing.instructions.md.
                                context.go(WorkspaceNav.clearAll());
                              },
                              toolTip: L10n.of(context).world,
                              naviRailWidth: naviRailWidth,
                            ),
                            // 2. Chats — the chat list. Chromeless (no box fill) and
                            // icon-sized to match the brand mark / course avatars
                            // (it used to render tiny on the default surface fill);
                            // the left indicator bar conveys selection.
                            NaviRailItem(
                              isSelected: isChats,
                              backgroundColor: Colors.transparent,
                              icon: Icon(
                                Icons.forum_outlined,
                                size: smallIconWidth,
                              ),
                              selectedIcon: Icon(
                                Icons.forum,
                                size: smallIconWidth,
                              ),
                              onTap: () {
                                // Token-only: the chats list is a left `chats` token
                                // over the world path `/` (no legacy `/chats` path).
                                context.go(
                                  WorkspaceNav.setSection(
                                    state.uri,
                                    const ChatsPanelToken(),
                                    // Replace open left panels rather than stack.
                                    keepRoom: false,
                                  ),
                                );
                              },
                              toolTip: L10n.of(context).allChats,
                              unreadBadgeFilter: (room) =>
                                  room.firstSpaceParent == null,
                              naviRailWidth: naviRailWidth,
                            ),
                            // 3. Courses — opens the Courses panel (the courses
                            // you're in + add-course options) as a bare `addcourse`
                            // left token. The Material map icon; chromeless, the bar
                            // conveys selection. keepRoom:false keeps it a focused
                            // flow with no chat floating over it. (Analytics is not a
                            // rail section — it opens from the top-right cluster.)
                            NaviRailItem(
                              isSelected: isCourseFind,
                              backgroundColor: Colors.transparent,
                              icon: Icon(
                                Icons.map_outlined,
                                size: smallIconWidth,
                              ),
                              selectedIcon: Icon(
                                Icons.map,
                                size: smallIconWidth,
                              ),
                              onTap: () {
                                context.go(
                                  WorkspaceNav.openAddCourse(state.uri),
                                );
                              },
                              toolTip: L10n.of(context).courses,
                              naviRailWidth: naviRailWidth,
                            ),
                            Semantics(
                              label: L10n.of(context).joinedCourseListLabel,
                              child: ListView(
                                shrinkWrap: true,
                                scrollDirection: Axis.vertical,
                                children: [
                                  // 4. The course spaces you're in.
                                  for (final space in allSpaces)
                                    // _spaceItem(context, space),
                                    _SpaceItem(
                                      space: space,
                                      iconWidth: largeIconWidth,
                                      naviRailWidth: naviRailWidth,
                                      // Highlight the course avatar only while the course
                                      // IS the open section — not merely because `?c=`
                                      // persists under a chat/room (routing decision 5).
                                      selected:
                                          section == AppSection.courses &&
                                          activeSpaceId == space.id,
                                      onTap: () =>
                                          _onTapSpace(context, space.id),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SpaceItem extends StatelessWidget {
  final Room space;
  final double iconWidth;
  final double naviRailWidth;
  final bool selected;
  final VoidCallback onTap;

  const _SpaceItem({
    required this.space,
    required this.iconWidth,
    required this.naviRailWidth,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayname = space.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final spaceChildrenIds = space.spaceChildren.map((c) => c.roomId).toSet();
    return NaviRailItem(
      toolTip: displayname,
      isSelected: selected,
      backgroundColor: Colors.transparent,
      borderRadius: BorderRadius.circular(0),
      onTap: onTap,
      unreadBadgeFilter: (room) => spaceChildrenIds.contains(room.id),
      icon: b.Badge(
        showBadge: space.membership == Membership.invite,
        badgeStyle: b.BadgeStyle(
          badgeColor: Theme.of(context).colorScheme.error,
          elevation: 4,
          borderSide: BorderSide.none,
          padding: const EdgeInsetsGeometry.all(0),
        ),
        badgeContent: Icon(
          Icons.error_outline,
          color: Theme.of(context).colorScheme.onPrimary,
          size: 16,
        ),
        position: b.BadgePosition.topEnd(top: -5, end: -7),
        child: ClipPath(
          clipper: MapClipper(),
          // The course name is already announced by NaviRailItem's toolTip, so
          // exclude the avatar's own name label to avoid a double-read (#7185).
          child: ExcludeSemantics(
            child: Avatar(
              mxContent: space.avatar,
              name: displayname,
              border: BorderSide(
                width: 1,
                color: Theme.of(context).dividerColor,
              ),
              borderRadius: BorderRadius.circular(0),
              size: iconWidth,
            ),
          ),
        ),
      ),
      naviRailWidth: naviRailWidth,
    );
  }
}

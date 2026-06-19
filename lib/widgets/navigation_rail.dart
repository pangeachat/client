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
import 'package:fluffychat/features/navigation/route_paths.dart';
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
  // #Pangea
  final GoRouterState state;
  // Pangea#
  final String? activeSpaceId;
  // #Pangea
  // final void Function() onGoToChats;
  // final void Function(String) onGoToSpaceId;
  final double naviRailWidth;
  final double expandedSectionWidth;
  final bool expanded;
  final VoidCallback collapse;
  final Profile? profile;
  final Function(Profile) onProfileUpdate;
  // Pangea#

  const SpacesNavigationRail({
    // #Pangea
    required this.state,
    // Pangea#
    required this.activeSpaceId,
    // #Pangea
    // required this.onGoToChats,
    // required this.onGoToSpaceId,
    required this.naviRailWidth,
    required this.expandedSectionWidth,
    required this.collapse,
    required this.onProfileUpdate,
    this.expanded = false,
    this.profile,
    // Pangea#
    super.key,
  });

  // #Pangea
  Future<void> _onTapSpace(BuildContext context, String roomId) async {
    collapse();
    final uri = GoRouterState.of(context).uri;
    final client = Matrix.of(context).client;
    final room = client.getRoomById(roomId);
    final membership = room?.membership;

    if (!{Membership.invite, Membership.leave}.contains(membership)) {
      context.go(
        WorkspaceNav.setSection(
          uri,
          PRoutes.course(roomId),
          const PanelToken('course'),
          // A left-nav click replaces the open left panels rather than stacking
          // beside them (drop any open room/section). See routing.instructions.md.
          keepRoom: false,
        ),
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
      WorkspaceNav.setSection(
        uri,
        PRoutes.course(joinedRoomId),
        const PanelToken('course'),
        keepRoom: false,
      ),
    );
    return;
  }

  /// A joined course space rail item (avatar + invite badge, map-clipped).
  Widget _spaceItem(BuildContext context, Room space) {
    final displayname = space.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final spaceChildrenIds = space.spaceChildren
        .map((c) => c.roomId)
        .toSet();
    final isColumnMode = FluffyThemes.isColumnMode(context);
    return NaviRailItem(
      toolTip: displayname,
      isSelected: activeSpaceId == space.id,
      backgroundColor: Colors.transparent,
      borderRadius: BorderRadius.circular(0),
      onTap: () => _onTapSpace(context, space.id),
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
          child: Avatar(
            mxContent: space.avatar,
            name: displayname,
            border: BorderSide(
              width: 1,
              color: Theme.of(context).dividerColor,
            ),
            borderRadius: BorderRadius.circular(0),
            size: naviRailWidth - (isColumnMode ? 32.0 : 24.0),
          ),
        ),
      ),
      expanded: expanded,
      naviRailWidth: naviRailWidth,
      expandedSectionWidth: expandedSectionWidth,
    );
  }
  // Pangea#

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    // #Pangea
    // world_v2: section + active space from route_facts (the single resolver),
    // using the shell's state so the rail can't disagree with the shell.
    final section = sectionFor(state.uri);
    final isChats = section == AppSection.chats;
    final isWorld = section == AppSection.world;
    // The Add-course / find-course flow: courses section, no active space.
    final isCourseFind =
        section == AppSection.courses && activeSpaceId == null;
    final isColumnMode = FluffyThemes.isColumnMode(context);

    // return StreamBuilder(
    // world_v2: the rail floats over the persistent map in the shared dock pill
    // (rounded, surface, elevated, outline-bordered) — the same chrome as the
    // top-right cluster, one source of truth. See workspace_dock.dart.
    return WorkspaceDock(
      child: SafeArea(
        child: StreamBuilder(
          // Pangea#
          key: ValueKey(client.userID.toString()),
          stream: client.onSync.stream
              .where((s) => s.hasRoomUpdate)
              .rateLimit(const Duration(seconds: 1)),
          builder: (context, _) {
            final allSpaces = client.rooms
                .where((room) => room.isSpace)
                .toList();

            // #Pangea
            // return SizedBox(
            return AnimatedContainer(
              // width: FluffyThemes.navRailWidth,
              width: expanded
                  ? naviRailWidth + expandedSectionWidth
                  : naviRailWidth,
              duration: FluffyThemes.animationDuration,
              // Pangea#
              // world_v2 rail order (top→bottom): World · Chats · Courses ·
              // joined spaces. (Profile/settings is no longer a rail slot;
              // analytics opens from the top-right cluster.)
              child: Column(
                // #Pangea
                // Size the rail to its items — a floating bar over the map, not
                // the full screen height; it still scrolls if the joined-spaces
                // list overflows the viewport.
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                // Pangea#
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
                          icon: PangeaLogoSvg(
                            width: naviRailWidth - (isColumnMode ? 32.0 : 24.0),
                            forceColor: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          selectedIcon: PangeaLogoSvg(
                            width: naviRailWidth - (isColumnMode ? 32.0 : 24.0),
                            forceColor: Theme.of(context).colorScheme.primary,
                          ),
                          onTap: () {
                            collapse();
                            // World is home: clear every panel (both columns)
                            // and reveal the full map. See routing.instructions.md.
                            context.go(WorkspaceNav.clearAll());
                          },
                          toolTip: L10n.of(context).world,
                          expanded: expanded,
                          naviRailWidth: naviRailWidth,
                          expandedSectionWidth: expandedSectionWidth,
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
                            size: naviRailWidth - (isColumnMode ? 40.0 : 32.0),
                          ),
                          selectedIcon: Icon(
                            Icons.forum,
                            size: naviRailWidth - (isColumnMode ? 40.0 : 32.0),
                          ),
                          onTap: () {
                            collapse();
                            // Token-only: the chats list is a left `chats` token
                            // over the world path `/` (no legacy `/chats` path).
                            context.go(
                              WorkspaceNav.setSection(
                                state.uri,
                                PRoutes.world,
                                const PanelToken('chats'),
                                // Replace open left panels rather than stack.
                                keepRoom: false,
                              ),
                            );
                          },
                          toolTip: L10n.of(context).allChats,
                          unreadBadgeFilter: (room) =>
                              room.firstSpaceParent == null,
                          expanded: expanded,
                          naviRailWidth: naviRailWidth,
                          expandedSectionWidth: expandedSectionWidth,
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
                            size: naviRailWidth - (isColumnMode ? 40.0 : 32.0),
                          ),
                          selectedIcon: Icon(
                            Icons.map,
                            size: naviRailWidth - (isColumnMode ? 40.0 : 32.0),
                          ),
                          onTap: () {
                            collapse();
                            context.go(
                              WorkspaceNav.setSection(
                                state.uri,
                                PRoutes.world,
                                const PanelToken('addcourse'),
                                keepRoom: false,
                              ),
                            );
                          },
                          toolTip: L10n.of(context).courses,
                          expanded: expanded,
                          naviRailWidth: naviRailWidth,
                          expandedSectionWidth: expandedSectionWidth,
                        ),
                        // 4. The course spaces you're in.
                        for (final space in allSpaces)
                          _spaceItem(context, space),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

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
    return Material(
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
              // world_v2 rail order (top→bottom): World · joined spaces ·
              // Chats · Add-course. (Profile/settings is no longer a rail slot.)
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
                        // World map home — the Pangea brand mark, at the top of
                        // the rail. Chromeless and avatar-sized; the left
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
                        // Joined course spaces.
                        for (final space in allSpaces)
                          _spaceItem(context, space),
                        // Chats.
                        NaviRailItem(
                          isSelected: isChats,
                          icon: const Icon(Icons.forum_outlined),
                          selectedIcon: const Icon(Icons.forum),
                          onTap: () {
                            collapse();
                            context.go(
                              WorkspaceNav.setSection(
                                state.uri,
                                PRoutes.chats,
                                const PanelToken('chats'),
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
                        // Analytics is no longer a rail section — it opens from
                        // the world map's top-right cluster trackers as a
                        // right-docked panel. See world-user-cluster.instructions.md.
                        // Add course — the find/add-course section in the
                        // left column (same as the other sections), not a
                        // popover. world_v2.
                        NaviRailItem(
                          backgroundColor: Colors.transparent,
                          borderRadius: BorderRadius.circular(0),
                          isSelected: isCourseFind,
                          onTap: () {
                            collapse();
                            // The add-course hub is a focused full-bleed flow:
                            // no section panel, and no chat floating over it.
                            context.go(
                              WorkspaceNav.setSection(
                                state.uri,
                                PRoutes.courses,
                                null,
                                keepRoom: false,
                              ),
                            );
                          },
                          icon: ClipPath(
                            clipper: MapClipper(),
                            child: Container(
                              width:
                                  naviRailWidth - (isColumnMode ? 32.0 : 24.0),
                              height:
                                  naviRailWidth - (isColumnMode ? 32.0 : 24.0),
                              color: isCourseFind
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHigh,
                              child: const Icon(Icons.add),
                            ),
                          ),
                          toolTip: L10n.of(context).addCourse,
                          expanded: expanded,
                          naviRailWidth: naviRailWidth,
                          expandedSectionWidth: expandedSectionWidth,
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
    );
  }
}

import 'package:flutter/material.dart';

import 'package:badges/badges.dart' as b;
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/features/course_plans/map_clipper.dart';
import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/utils/chat_list_handle_space_tap.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/navi_rail_item.dart';

class SpacesNavigationRail extends StatelessWidget {
  final String? activeSpaceId;
  // #Pangea
  // final void Function() onGoToChats;
  // final void Function(String) onGoToSpaceId;
  final String? path;
  final double naviRailWidth;
  final double expandedSectionWidth;
  final bool expanded;
  final VoidCallback collapse;
  final Profile? profile;
  final Function(Profile) onProfileUpdate;
  // Pangea#

  const SpacesNavigationRail({
    required this.activeSpaceId,
    // #Pangea
    // required this.onGoToChats,
    // required this.onGoToSpaceId,
    required this.path,
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
    final client = Matrix.of(context).client;
    final room = client.getRoomById(roomId);
    final membership = room?.membership;

    if (!{Membership.invite, Membership.leave}.contains(membership)) {
      context.go(PRoutes.course(roomId));
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

    context.go(PRoutes.course(joinedRoomId));
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
    // world_v2: exact section resolution via AppSection — no substring
    // matching on paths.
    final section = AppSection.fromUri(
      GoRouter.of(context).routeInformationProvider.value.uri,
    );
    final isSettings = section == AppSection.settings;
    final isUserHome = section == AppSection.profile;
    final isAnalytics = section == AppSection.analytics;
    final isChats = section == AppSection.chats;
    final isWorld = section == AppSection.world;
    // The Add-course / find-course flow: courses section, no active space.
    final isCourseFind =
        section == AppSection.courses &&
        AppSection.activeSpaceId(
              GoRouter.of(context).routeInformationProvider.value.uri,
            ) ==
            null;
    // The Avatar slot merges profile + settings (world_v2).
    final isAvatar = isUserHome || isSettings;
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
              // world_v2 rail order (top→bottom): Avatar (profile+settings) ·
              // joined spaces · Chats · Analytics · World · Add-course.
              // Settings folds into the Avatar surface — no bottom slot.
              child: Column(
                // #Pangea
                crossAxisAlignment: CrossAxisAlignment.start,
                // Pangea#
                children: [
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.vertical,
                      children: [
                        // Avatar — profile + settings.
                        NaviRailItem(
                          isSelected: isAvatar,
                          onTap: () {
                            collapse();
                            context.go(PRoutes.profile);
                          },
                          backgroundColor: Colors.transparent,
                          icon: FutureBuilder<Profile>(
                            initialData: profile,
                            future: client.fetchOwnProfile(),
                            builder: (context, snapshot) {
                              if (snapshot.data?.avatarUrl != null &&
                                  snapshot.data?.avatarUrl !=
                                      profile?.avatarUrl) {
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => onProfileUpdate(snapshot.data!),
                                );
                              }
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(99),
                                    child: Avatar(
                                      mxContent: snapshot.data?.avatarUrl,
                                      name:
                                          snapshot.data?.displayName ??
                                          client.userID!.localpart,
                                      size:
                                          naviRailWidth -
                                          (isColumnMode ? 32.0 : 24.0),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          toolTip: L10n.of(context).home,
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
                            context.go(PRoutes.chats);
                          },
                          toolTip: L10n.of(context).allChats,
                          unreadBadgeFilter: (room) =>
                              room.firstSpaceParent == null,
                          expanded: expanded,
                          naviRailWidth: naviRailWidth,
                          expandedSectionWidth: expandedSectionWidth,
                        ),
                        // Analytics.
                        NaviRailItem(
                          isSelected: isAnalytics,
                          icon: const Icon(Icons.analytics_outlined),
                          selectedIcon: const Icon(Icons.analytics),
                          onTap: () {
                            collapse();
                            AnalyticsNavigationUtil.navigateToAnalytics(
                              context: context,
                            );
                          },
                          toolTip: L10n.of(context).learningAnalytics,
                          expanded: expanded,
                          naviRailWidth: naviRailWidth,
                          expandedSectionWidth: expandedSectionWidth,
                        ),
                        // World map home.
                        NaviRailItem(
                          isSelected: isWorld,
                          icon: const Icon(Icons.public_outlined),
                          selectedIcon: const Icon(Icons.public),
                          onTap: () {
                            collapse();
                            context.go(PRoutes.world);
                          },
                          toolTip: L10n.of(context).world,
                          expanded: expanded,
                          naviRailWidth: naviRailWidth,
                          expandedSectionWidth: expandedSectionWidth,
                        ),
                        // Add course — the find/add-course section in the
                        // left column (same as the other sections), not a
                        // popover. world_v2.
                        NaviRailItem(
                          backgroundColor: Colors.transparent,
                          borderRadius: BorderRadius.circular(0),
                          isSelected: isCourseFind,
                          onTap: () {
                            collapse();
                            context.go(PRoutes.courses);
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

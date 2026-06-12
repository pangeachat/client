import 'package:flutter/material.dart';

import 'package:badges/badges.dart' as b;
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/navi_rail_item.dart';
import 'package:fluffychat/pangea/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/pangea/analytics_misc/analytics_navigation_util.dart';
import 'package:fluffychat/pangea/chat_list/utils/chat_list_handle_space_tap.dart';
import 'package:fluffychat/pangea/course_plans/map_clipper.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/pangea/navigation/app_section.dart';
import 'package:fluffychat/pangea/navigation/route_paths.dart';
import 'package:fluffychat/widgets/matrix.dart';

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
    final isCourse =
        section == AppSection.courses &&
        AppSection.activeSpaceId(
              GoRouter.of(context).routeInformationProvider.value.uri,
            ) ==
            null;
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
              child: Column(
                // #Pangea
                crossAxisAlignment: CrossAxisAlignment.start,
                // Pangea#
                children: [
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.vertical,
                      // #Pangea
                      // itemCount: allSpaces.length + 2,
                      itemCount: allSpaces.length + 4,
                      // Pangea#
                      itemBuilder: (context, i) {
                        // #Pangea
                        if (i == 0) {
                          return NaviRailItem(
                            isSelected: isUserHome,
                            onTap: () {
                              collapse();
                              context.go(PRoutes.profile);
                            },
                            backgroundColor: Colors.transparent,
                            icon: FutureBuilder<Profile>(
                              // #Pangea
                              initialData: profile,
                              // Pangea#
                              future: client.fetchOwnProfile(),
                              // #Pangea
                              // builder: (context, snapshot) => Stack(
                              builder: (context, snapshot) {
                                if (snapshot.data?.avatarUrl != null &&
                                    snapshot.data?.avatarUrl !=
                                        profile?.avatarUrl) {
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => onProfileUpdate(snapshot.data!),
                                  );
                                }
                                return Stack(
                                  // Pangea#
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
                            // #Pangea
                            expanded: expanded,
                            naviRailWidth: naviRailWidth,
                            expandedSectionWidth: expandedSectionWidth,
                            // Pangea#
                          );
                        }
                        i--;
                        if (i == 0) {
                          return NaviRailItem(
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
                          );
                        }
                        i--;
                        // Pangea#
                        if (i == 0) {
                          return NaviRailItem(
                            // #Pangea
                            // isSelected: activeSpaceId == null && !isSettings,
                            isSelected:
                                activeSpaceId == null &&
                                !isSettings &&
                                !isAnalytics &&
                                !isUserHome &&
                                !isCourse,
                            // onTap: onGoToChats,
                            // icon: const Padding(
                            //   padding: EdgeInsets.all(10.0),
                            //   child: Icon(Icons.forum_outlined),
                            // ),
                            // selectedIcon: const Padding(
                            //   padding: EdgeInsets.all(10.0),
                            //   child: Icon(Icons.forum),
                            // ),
                            // toolTip: L10n.of(context).chats,
                            // unreadBadgeFilter: (room) => true,
                            icon: const Icon(Icons.forum_outlined),
                            selectedIcon: const Icon(Icons.forum),
                            onTap: () {
                              collapse();
                              context.go(PRoutes.world);
                            },
                            toolTip: L10n.of(context).allChats,
                            unreadBadgeFilter: (room) =>
                                room.firstSpaceParent == null,
                            expanded: expanded,
                            naviRailWidth: naviRailWidth,
                            expandedSectionWidth: expandedSectionWidth,
                            // Pangea#
                          );
                        }
                        i--;
                        if (i == allSpaces.length) {
                          return NaviRailItem(
                            // #Pangea
                            // isSelected: false,
                            // onTap: () => context.go('/rooms/newspace'),
                            // icon: const Padding(
                            //   padding: EdgeInsets.all(8.0),
                            //   child: Icon(Icons.add),
                            // ),
                            // toolTip: L10n.of(context).createNewSpace,
                            backgroundColor: Colors.transparent,
                            borderRadius: BorderRadius.circular(0),
                            isSelected: isCourse,
                            onTap: () {
                              collapse();
                              context.go(PRoutes.courses);
                            },
                            icon: ClipPath(
                              clipper: MapClipper(),
                              child: Container(
                                width:
                                    naviRailWidth -
                                    (isColumnMode ? 32.0 : 24.0),
                                height:
                                    naviRailWidth -
                                    (isColumnMode ? 32.0 : 24.0),
                                color: isCourse
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
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
                            // Pangea#
                          );
                        }
                        final space = allSpaces[i];
                        final displayname = allSpaces[i]
                            .getLocalizedDisplayname(
                              MatrixLocals(L10n.of(context)),
                            );
                        final spaceChildrenIds = space.spaceChildren
                            .map((c) => c.roomId)
                            .toSet();
                        return NaviRailItem(
                          toolTip: displayname,
                          isSelected: activeSpaceId == space.id,
                          // #Pangea
                          backgroundColor: Colors.transparent,
                          borderRadius: BorderRadius.circular(0),
                          // onTap: () => onGoToSpaceId(allSpaces[i].id),
                          onTap: () => _onTapSpace(context, allSpaces[i].id),
                          // Pangea#
                          unreadBadgeFilter: (room) =>
                              spaceChildrenIds.contains(room.id),
                          // #Pangea
                          // icon: Avatar(
                          //   mxContent: allSpaces[i].avatar,
                          //   name: displayname,
                          //   border: BorderSide(
                          //     width: 1,
                          //     color: Theme.of(context).dividerColor,
                          //   ),
                          //   borderRadius: BorderRadius.circular(
                          //     AppConfig.borderRadius / 2,
                          //   ),
                          // ),
                          icon: b.Badge(
                            showBadge:
                                allSpaces[i].membership == Membership.invite,
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
                                mxContent: allSpaces[i].avatar,
                                name: displayname,
                                border: BorderSide(
                                  width: 1,
                                  color: Theme.of(context).dividerColor,
                                ),
                                borderRadius: BorderRadius.circular(0),
                                size:
                                    naviRailWidth -
                                    (isColumnMode ? 32.0 : 24.0),
                              ),
                            ),
                          ),
                          expanded: expanded,
                          naviRailWidth: naviRailWidth,
                          expandedSectionWidth: expandedSectionWidth,
                          // Pangea#
                        );
                      },
                    ),
                  ),
                  // #Pangea
                  // NaviRailItem(
                  SizedBox(
                    width: expanded
                        ? naviRailWidth + expandedSectionWidth
                        : naviRailWidth,
                    child: NaviRailItem(
                      // Pangea#
                      isSelected: isSettings,
                      // #Pangea
                      // onTap: () => context.go(PRoutes.settings),
                      // icon: const Padding(
                      //   padding: EdgeInsets.all(10.0),
                      //   child: Icon(Icons.settings_outlined),
                      // ),
                      // selectedIcon: const Padding(
                      //   padding: EdgeInsets.all(10.0),
                      //   child: Icon(Icons.settings),
                      // ),
                      onTap: () {
                        collapse();
                        context.go(PRoutes.settings);
                      },
                      icon: const Icon(Icons.settings_outlined),
                      selectedIcon: const Icon(Icons.settings),
                      expanded: expanded,
                      naviRailWidth: naviRailWidth,
                      expandedSectionWidth: expandedSectionWidth,
                      // Pangea#
                      toolTip: L10n.of(context).settings,
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

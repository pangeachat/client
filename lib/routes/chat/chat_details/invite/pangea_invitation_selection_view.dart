import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/join_codes/share_room_button.dart';
import 'package:fluffychat/features/user/widgets/user_filter_chip_row.dart';
import 'package:fluffychat/features/user/widgets/user_result_tile.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/room_unavailable_panel.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/invite_all_in_space_tile.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/room_settings_constants.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';
import 'package:fluffychat/widgets/users/member_actions_popup_menu_button.dart';

class PangeaInvitationSelectionView extends StatelessWidget {
  final PangeaInvitationSelectionController controller;

  const PangeaInvitationSelectionView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final room = Matrix.of(
      context,
    ).client.getRoomById(controller.widget.roomId);
    if (room == null) {
      return RoomUnavailablePanel(
        closeButton: controller.widget.embeddedCloseButton,
      );
    }

    final theme = Theme.of(context);

    // The invite page is URL-addressable, so hiding entry buttons (#7875)
    // can't keep a member without invite power out of it — and for them every
    // invite action can only fail with M_FORBIDDEN (#8694 / CLIENT-DCA). The
    // page stays browsable (it doubles as a roster view); only the invite
    // affordances disable, with a note saying why. Sharing the class code
    // stays available: the join-code module issues its invites through a
    // member that has the power.
    final canInvite = room.canInvite;

    return Semantics(
      label: L10n.of(context).pageLabel(L10n.of(context).inviteContact),
      container: true,
      child: Scaffold(
        appBar: AppBar(
          leading: Center(child: controller.widget.embeddedCloseButton),
          titleSpacing: 0,
          title: Text(
            L10n.of(context).inviteContact,
            style: FluffyThemes.isColumnMode(context)
                ? theme.textTheme.titleLarge
                : theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
          ),
          centerTitle: false,
          actions: [
            Padding(
              padding: .only(
                right: FluffyThemes.isColumnMode(context) ? 0 : 16,
              ),
              child: ShareRoomButton(
                room: room,
                tooltip: L10n.of(context).share,
                icon: const Icon(Icons.share_outlined),
              ),
            ),
          ],
        ),
        body: MaxWidthBody(
          maxWidth: 800.0,
          withScrolling: false,
          showBorder: false,
          padding: const EdgeInsets.all(0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              spacing: 12.0,
              children: [
                if (!canInvite)
                  Text(
                    L10n.of(context).noPermissionToInviteUsers,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                PangeaSearchBar(
                  labelText: L10n.of(context).searchUsersHint,
                  controller: controller.controller,
                  onChanged: controller.searchUserWithCoolDown,
                  prefixIcon: controller.loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 10.0,
                            horizontal: 12,
                          ),
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : null,
                ),
                UserFilterChipRow(
                  chips: controller.availableFilters
                      .map(
                        (filter) => UserFilterChip(
                          label: controller.filterLabel(filter),
                          icon: filter == InvitationFilter.participants
                              ? Icons.group
                              : null,
                          selected: controller.filter == filter,
                          onSelected: () => controller.setFilter(filter),
                        ),
                      )
                      .toList(),
                ),
                Expanded(
                  child: StreamBuilder<Object>(
                    stream: room.client.onRoomState.stream
                        .where((update) => update.roomId == room.id)
                        .rateLimit(const Duration(seconds: 1)),
                    builder: (context, snapshot) {
                      // Computed together, from the same room-state event, so
                      // the accept-all button, participant badges, and the
                      // list's contents/order never fall out of sync with
                      // each other (#8513).
                      final contacts = controller.filteredContacts();
                      final participants = room
                          .getParticipants()
                          .map((user) => user.id)
                          .toSet();

                      return Column(
                        spacing: 12.0,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: controller.showAcceptAll
                                ? ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          theme.colorScheme.primaryContainer,
                                      foregroundColor:
                                          theme.colorScheme.onPrimaryContainer,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                    ),
                                    label: Text(L10n.of(context).acceptAll),
                                    // Accepting a knock issues an
                                    // invite, so it needs the same
                                    // power the invite buttons do.
                                    onPressed: canInvite
                                        ? controller.acceptAllKnocking
                                        : null,
                                  )
                                : const SizedBox.shrink(),
                          ),
                          Expanded(
                            child: Semantics(
                              label: L10n.of(context).results,
                              container: true,
                              child:
                                  controller.filter == InvitationFilter.public
                                  ? controller.foundProfiles.isEmpty
                                        ? Padding(
                                            padding: const EdgeInsets.all(24.0),
                                            child: Text(
                                              // A failed search must not read
                                              // as "nobody by that name" —
                                              // the directory is rate-limited,
                                              // so a burst of keystrokes can
                                              // answer 429 (#9009).
                                              controller.searchError != null
                                                  ? controller.searchError!
                                                        .toLocalizedString(
                                                          context,
                                                        )
                                                  : controller
                                                            .controller
                                                            .text
                                                            .isNotEmpty &&
                                                        controller
                                                                .controller
                                                                .text ==
                                                            controller
                                                                .lastSearch
                                                  ? L10n.of(
                                                      context,
                                                    ).emptyInviteSearchHint
                                                  : room.isSpace
                                                  ? L10n.of(
                                                      context,
                                                    ).publicInviteDescSpace
                                                  : L10n.of(
                                                      context,
                                                    ).publicInviteDescChat,
                                            ),
                                          )
                                        : ListView.builder(
                                            controller:
                                                controller.scrollController,
                                            itemCount:
                                                controller.foundProfiles.length,
                                            itemBuilder:
                                                (
                                                  BuildContext context,
                                                  int i,
                                                ) => _InviteContactListTile(
                                                  profile: controller
                                                      .foundProfiles[i],
                                                  isMember: participants
                                                      .contains(
                                                        controller
                                                            .foundProfiles[i]
                                                            .userId,
                                                      ),
                                                  canInvite: canInvite,
                                                  onTap: () =>
                                                      controller.inviteAction(
                                                        controller
                                                            .foundProfiles[i]
                                                            .userId,
                                                      ),
                                                  controller: controller,
                                                ),
                                          )
                                  : ListView.builder(
                                      controller: controller.scrollController,
                                      itemCount: contacts.length + 2,
                                      itemBuilder: (BuildContext context, int i) {
                                        if (i == 0) {
                                          return controller
                                                  .showInviteAllInSpaceButton
                                              ? InviteAllInSpaceTile(
                                                  avatar: controller
                                                      .spaceParent!
                                                      .avatar,
                                                  displayname: controller
                                                      .spaceParent!
                                                      .getLocalizedDisplayname(),
                                                  memberCount:
                                                      controller
                                                          .spaceParent!
                                                          .summary
                                                          .mJoinedMemberCount ??
                                                      1,
                                                  onPressed: canInvite
                                                      ? controller
                                                            .inviteAllInSpace
                                                      : null,
                                                )
                                              : const SizedBox();
                                        }

                                        i--;

                                        if (i == contacts.length) {
                                          return ExcludeSemantics(
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                16.0,
                                              ),
                                              child: SizedBox(
                                                width: 450,
                                                child: CachedNetworkImage(
                                                  imageUrl:
                                                      "${AppConfig.assetsBaseURL}/${RoomSettingsConstants.referFriendAsset}",
                                                  errorWidget:
                                                      (context, url, error) =>
                                                          const SizedBox(),
                                                  placeholder: (context, url) =>
                                                      const Center(
                                                        child:
                                                            CircularProgressIndicator.adaptive(),
                                                      ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                        return _InviteContactListTile(
                                          user: contacts[i],
                                          profile: Profile(
                                            avatarUrl: contacts[i].avatarUrl,
                                            displayName:
                                                localizedPangeaUserName(
                                                  contacts[i].id,
                                                  L10n.of(context),
                                                ) ??
                                                contacts[i].displayName ??
                                                contacts[i].id.localpart ??
                                                L10n.of(context).user,
                                            userId: contacts[i].id,
                                          ),
                                          isMember: participants.contains(
                                            contacts[i].id,
                                          ),
                                          canInvite: canInvite,
                                          onTap: () => controller.inviteAction(
                                            contacts[i].id,
                                          ),
                                          controller: controller,
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
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

class _InviteContactListTile extends StatelessWidget {
  final Profile profile;
  final User? user;
  final bool isMember;

  /// Whether the viewer holds the room's invite power — false disables the
  /// trailing invite button (#8694).
  final bool canInvite;
  final void Function() onTap;
  final PangeaInvitationSelectionController controller;

  const _InviteContactListTile({
    required this.profile,
    this.user,
    required this.isMember,
    required this.canInvite,
    required this.onTap,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    final participant = controller.participants?.firstWhereOrNull(
      (p) => p.id == profile.userId,
    );
    final membership = participant?.membership;

    final String? permissionBatch = participant == null
        ? null
        : participant.powerLevel >= 100
        ? L10n.of(context).admin
        : participant.powerLevel >= 50
        ? L10n.of(context).moderator
        : null;

    return UserResultTile(
      profile: profile,
      onTap: participant != null
          ? () =>
                showMemberActionsPopupMenu(context: context, user: participant)
          : null,
      trailing:
          [
            Membership.invite,
            Membership.knock,
            Membership.ban,
          ].contains(membership)
          ? Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                controller.membershipCopy(membership)!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            )
          : permissionBatch != null
          ? Container(
              margin: const EdgeInsets.only(right: 12.0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: participant!.powerLevel >= 100
                    ? theme.pangea.goldFixedDim
                    : theme.pangea.goldContainer,
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              ),
              child: Text(
                permissionBatch,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: participant.powerLevel >= 100
                      ? theme.pangea.onGoldFixed
                      : theme.pangea.onGoldContainer,
                ),
              ),
            )
          : TextButton.icon(
              onPressed: isMember || !canInvite ? null : onTap,
              label: Text(isMember ? l10n.participant : l10n.invite),
              icon: Icon(isMember ? Icons.check : Icons.add),
            ),
    );
  }
}

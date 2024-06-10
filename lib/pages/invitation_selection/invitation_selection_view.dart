import 'package:fluffychat/pages/invitation_selection/invitation_selection.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

class InvitationSelectionView extends StatelessWidget {
  final InvitationSelectionController controller;

  const InvitationSelectionView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final room =
        Matrix.of(context).client.getRoomById(controller.widget.roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context)!.oopsSomethingWentWrong),
        ),
        body: Center(
          child: Text(L10n.of(context)!.youAreNoLongerParticipatingInThisChat),
        ),
      );
    }

    // #Pangea
    // final groupName = room.name.isEmpty ? L10n.of(context)!.group : room.name;
    // Pangea#
    return Scaffold(
      appBar: AppBar(
        // #Pangea
        // leading: const Center(child: BackButton()),
        leading: Center(
          child: BackButton(
            onPressed: () => context.go("/rooms/${controller.roomId}/details"),
          ),
        ),
// Pangea#
        titleSpacing: 0,
        title: Text(L10n.of(context)!.inviteContact),
      ),
      body: MaxWidthBody(
        innerPadding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  // #Pangea
                  hintText: controller.mode == InvitationSelectionMode.admin
                      ? L10n.of(context)!.inviteUsersFromPangea
                      : L10n.of(context)!.inviteStudentByUserName,
                  // hintText: L10n.of(context)!.inviteContactToGroup(groupName),
                  // Pangea#
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
                      : const Icon(Icons.search_outlined),
                ),
                onChanged: controller.searchUserWithCoolDown,
              ),
            ),
            StreamBuilder<Object>(
              stream: room.client.onRoomState.stream
                  .where((update) => update.roomId == room.id),
              builder: (context, snapshot) {
                final participants =
                    room.getParticipants().map((user) => user.id).toSet();
                if (controller.mode != InvitationSelectionMode.admin &&
                    room.spaceParents.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        L10n.of(context)!.emptyInviteWarning,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return controller.foundProfiles.isNotEmpty
                    ? ListView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: controller.foundProfiles.length,
                        itemBuilder: (BuildContext context, int i) =>
                            _InviteContactListTile(
                          avatarUrl: controller.foundProfiles[i].avatarUrl,
                          displayname: controller
                                  .foundProfiles[i].displayName ??
                              controller.foundProfiles[i].userId.localpart ??
                              L10n.of(context)!.user,
                          userId: controller.foundProfiles[i].userId,
                          isMember: participants
                              .contains(controller.foundProfiles[i].userId),
                          onTap: () => controller.inviteAction(
                            context,
                            controller.foundProfiles[i].userId,
                            controller.foundProfiles[i].displayName ??
                                controller.foundProfiles[i].userId.localpart ??
                                L10n.of(context)!.user,
                            // #Pangea
                            mode: controller.mode,
                            // Pangea#
                          ),
                        ),
                      )
                    : FutureBuilder<List<User>>(
                        // #Pangea
                        future: controller.mode == InvitationSelectionMode.admin
                            ? controller.getContacts(context)
                            : controller.eligibleStudents(context, ""),
                        // future: controller.getContacts(context),
                        // Pangea#
                        builder: (BuildContext context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            );
                          }
                          final contacts = snapshot.data!;
                          return ListView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: contacts.length,
                            itemBuilder: (BuildContext context, int i) =>
                                _InviteContactListTile(
                              avatarUrl: contacts[i].avatarUrl,
                              displayname: contacts[i].displayName ??
                                  contacts[i].id.localpart ??
                                  L10n.of(context)!.user,
                              userId: contacts[i].id,
                              isMember: participants.contains(contacts[i].id),
                              onTap: () => controller.inviteAction(
                                context,
                                contacts[i].id,
                                contacts[i].displayName ??
                                    contacts[i].id.localpart ??
                                    L10n.of(context)!.user,
                                // #Pangea
                                mode: controller.mode,
                                // Pangea#
                              ),
                            ),
                          );
                        },
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteContactListTile extends StatelessWidget {
  final String userId;
  final String displayname;
  final Uri? avatarUrl;
  final bool isMember;
  final void Function() onTap;

  const _InviteContactListTile({
    required this.userId,
    required this.displayname,
    required this.avatarUrl,
    required this.isMember,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isMember ? 0.5 : 1,
      child: ListTile(
        leading: Avatar(
          mxContent: avatarUrl,
          name: displayname,
          presenceUserId: userId,
        ),
        title: Text(
          displayname,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          userId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        onTap: isMember ? null : onTap,
        trailing: isMember
            ? Text(L10n.of(context)!.participant)
            : const Icon(Icons.person_add_outlined),
      ),
    );
  }
}

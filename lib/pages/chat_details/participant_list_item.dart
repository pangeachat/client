import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/avatar.dart';
import '../user_bottom_sheet/user_bottom_sheet.dart';

class ParticipantListItem extends StatelessWidget {
  final User user;

  const ParticipantListItem(this.user, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final membershipBatch = switch (user.membership) {
      Membership.ban => L10n.of(context)!.banned,
      Membership.invite => L10n.of(context)!.invited,
      Membership.join => null,
      Membership.knock => L10n.of(context)!.knocking,
      Membership.leave => L10n.of(context)!.leftTheChat,
    };

    final permissionBatch = user.powerLevel == 100
        ? L10n.of(context)!.admin
        : user.powerLevel >= 50
            ? L10n.of(context)!.moderator
            : '';

    return Opacity(
      opacity: user.membership == Membership.join ? 1 : 0.5,
      child: ListTile(
        onTap: () => showAdaptiveBottomSheet(
          context: context,
          builder: (c) => UserBottomSheet(
            user: user,
            outerContext: context,
          ),
        ),
        title: Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                // user.calcDisplayname(),
                "?",
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (permissionBatch.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2,
                ),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  // #Pangea
                  // color: theme.colorScheme.primaryContainer,
                  color: theme.secondaryHeaderColor,
                  // Pangea#
                  borderRadius: BorderRadius.circular(8),
                  // #Pangea
                  // border: Border.all(
                  //   color: theme.colorScheme.primary,
                  // ),
                  // Pangea#
                ),
                child: Text(
                  permissionBatch,
                  // #Pangea
                  // style: TextStyle(
                  //   fontSize: 14,
                  //   color: theme.colorScheme.primary,
                  // ),
                  // Pangea#
                ),
              ),
            membershipBatch == null
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.all(4),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: theme.secondaryHeaderColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: Text(membershipBatch)),
                  ),
          ],
        ),
        subtitle: Text(user.id),
        leading: Avatar(
          mxContent: user.avatarUrl,
          // name: user.calcDisplayname(),
          // presenceUserId: user.stateKey,
          name: "?",
        ),
      ),
    );
  }
}

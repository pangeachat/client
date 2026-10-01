import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/users/level_display_name.dart';

/// One person in a user-search result list — the row the invite page and the
/// New Direct Message panel both render (#9009).
///
/// Everything room-scoped lives in [trailing] and [onTap], which the host
/// supplies: the invite page passes its membership badge, power-level badge or
/// invite button, and the DM panel passes neither.
class UserResultTile extends StatelessWidget {
  final Profile profile;

  /// The row's own tap target. Null leaves the row inert — tapping the avatar
  /// still opens the profile, which is the DM panel's only action.
  final VoidCallback? onTap;

  final Widget? trailing;

  const UserResultTile({
    super.key,
    required this.profile,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Semantics(
      label: profile.displayName,
      container: true,
      child: ListTile(
        onTap: onTap,
        leading: Semantics(
          label: l10n.profile,
          container: true,
          child: ExcludeSemantics(
            child: Avatar(
              mxContent: profile.avatarUrl,
              name: profile.displayName,
              presenceUserId: profile.userId,
              onTap: () => UserDialog.show(
                context: context,
                profile: profile,
                uri: GoRouterState.of(context).uri,
              ),
            ),
          ),
        ),
        title: ExcludeSemantics(
          child: Text(
            profile.displayName ?? profile.userId.localpart ?? l10n.user,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // https://github.com/pangeachat/client/issues/3047
            const SizedBox(height: 2.0),
            Text(
              profile.userId,
              style: const TextStyle(fontSize: 12.0),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            LevelDisplayName(userId: profile.userId),
          ],
        ),
        trailing: trailing,
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/course_plans/map_clipper.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// Header of the contacts list on the invite page: the course this chat sits
/// in, plus a button to invite everyone in it.
///
/// A Row rather than a ListTile, whose trailing widget keeps its intrinsic
/// width and rides over the leading avatar once the label is long enough
/// (#7784). Here the label and the course name share the space left by the
/// avatar, so a long translation wraps instead.
class InviteAllInSpaceTile extends StatelessWidget {
  final Uri? avatar;
  final String displayname;
  final int memberCount;
  final VoidCallback onPressed;

  const InviteAllInSpaceTile({
    required this.avatar,
    required this.displayname,
    required this.memberCount,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        spacing: 12.0,
        children: [
          ClipPath(
            clipper: MapClipper(),
            child: Avatar(
              mxContent: avatar,
              name: displayname,
              borderRadius: BorderRadius.circular(AppConfig.borderRadius / 4),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                Text(
                  L10n.of(context).countParticipants(memberCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onPressed,
                label: Text(L10n.of(context).inviteAllInSpace),
                icon: const Icon(Icons.add),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

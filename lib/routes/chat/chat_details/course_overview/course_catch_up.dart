import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/pangea/spaces/knocking_users_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// The course page's notifications section ("Catch up", #8357): a gold
/// attention card at the top of the page, rendered only when something needs
/// the user's action — a bell with the unread count beside the section title,
/// rows capped at [_maxCollapsedRows] with a load-more expander so a pile of
/// notifications never overwhelms the page.
///
/// v1 rows are join requests (admin-only, via [KnockingUsersBuilder]); other
/// notification kinds slot in as further row sources.
class CourseCatchUp extends StatefulWidget {
  final Room room;

  const CourseCatchUp({required this.room, super.key});

  @override
  State<CourseCatchUp> createState() => _CourseCatchUpState();
}

class _CourseCatchUpState extends State<CourseCatchUp> {
  static const int _maxCollapsedRows = 2;

  bool _expanded = false;

  /// Approve routes through the existing invite page seated on the knock
  /// filter — the reviewed accept/deny flow (#8139).
  void _openKnockReview(BuildContext context) => context.go(
    WorkspaceNav.openCoursePage(
      GoRouterState.of(context).uri,
      RoomSubpageEnum.invite,
      filter: InvitationFilter.knocking,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return KnockingUsersBuilder(
      room: widget.room,
      builder: (context, knockingUsers) {
        if (knockingUsers.isEmpty) return const SizedBox.shrink();
        final visible = _expanded
            ? knockingUsers
            : knockingUsers.take(_maxCollapsedRows).toList();
        final hiddenCount = knockingUsers.length - visible.length;
        final gold = AppConfig.goldByTheme(context);
        final l10n = L10n.of(context);
        return Semantics(
          label: l10n.catchUp,
          container: true,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12.0),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: gold.withAlpha(30),
              border: Border.all(color: gold.withAlpha(120)),
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Badge.count(
                      count: knockingUsers.length,
                      child: const Icon(
                        Icons.notifications_outlined,
                        size: 20.0,
                      ),
                    ),
                    const SizedBox(width: 10.0),
                    Text(
                      l10n.catchUp,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4.0),
                ...visible.map(
                  (user) => _CatchUpKnockRow(
                    user: user,
                    onApprove: () => _openKnockReview(context),
                  ),
                ),
                if (hiddenCount > 0)
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _expanded = true),
                      child: Text(
                        l10n.loadMore,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One join request: the knocking user's avatar and name, with an Approve
/// action opening the knock-review flow.
class _CatchUpKnockRow extends StatelessWidget {
  final User user;
  final VoidCallback onApprove;

  const _CatchUpKnockRow({required this.user, required this.onApprove});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final displayname = user.localizedDisplayname(l10n);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        children: [
          Avatar(mxContent: user.avatarUrl, name: displayname, size: 34.0),
          const SizedBox(width: 10.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  l10n.knocking,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: onApprove,
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(
              l10n.approve,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

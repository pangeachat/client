import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/pangea/spaces/knocking_users_badge.dart';
import 'package:fluffychat/pangea/spaces/knocking_users_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_attention_card.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/users/member_actions_popup_menu_button.dart';

/// The course page's join-request card (#8462): the users knocking on the
/// course, under the same red "!" the course avatar wears while a knock is
/// pending, so the badge that sent the admin here and the card they land on
/// read as one alert. Admin-only — [KnockingUsersBuilder] hands back an empty
/// list for everyone else, and the card renders nothing.
///
/// Its own card rather than rows inside `CourseCatchUp`: a knock is a decision
/// waiting on the admin, not something to mark read, so it carries "Deny all
/// users" and no dismissal layer.
class CourseKnockRequests extends StatelessWidget {
  final Room room;

  const CourseKnockRequests({required this.room, super.key});

  /// Approve routes through the existing invite page seated on the knock
  /// filter — the reviewed accept/deny flow (#8139).
  void _openKnockReview(BuildContext context) => context.go(
    WorkspaceNav.openCoursePage(
      GoRouterState.of(context).uri,
      RoomSubpageEnum.invite,
      filter: InvitationFilter.knocking,
    ),
  );

  /// Deny every pending request at once. Each knocker is kicked, which is what
  /// a single Deny does, so the card and the course's "!" badge both clear off
  /// the resulting member events — no reload.
  Future<void> _denyAll(BuildContext context, List<User> knockingUsers) async {
    final l10n = L10n.of(context);
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: l10n.areYouSure,
      message: l10n.denyAllKnocksDescription,
      okLabel: l10n.yes,
      cancelLabel: l10n.no,
    );
    if (consent != OkCancelResult.ok || !context.mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => Future.wait(knockingUsers.map((user) => user.kick())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return KnockingUsersBuilder(
      room: room,
      builder: (context, knockingUsers) => CourseAttentionCard(
        icon: CircleAvatar(
          radius: CourseAttentionCard.iconSize / 2,
          backgroundColor: theme.colorScheme.error,
          child: Icon(
            KnockingUsersBadge.icon,
            size: CourseAttentionCard.insetIconSize,
            color: theme.colorScheme.onError,
          ),
        ),
        title: l10n.usersAreTryingToJoinCourse,
        actionLabel: l10n.denyAllUsers,
        onAction: () => _denyAll(context, knockingUsers),
        rows: knockingUsers
            .map(
              (user) => _KnockRequestRow(
                user: user,
                room: room,
                onApprove: () => _openKnockReview(context),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// One join request: the knocking user's avatar and name, with an Approve
/// action opening the knock-review flow. Tapping the avatar opens the member
/// actions menu — profile, description, and a DM — so an admin can vet a
/// stranger before letting them in (#8462).
class _KnockRequestRow extends StatelessWidget {
  final User user;
  final Room room;
  final VoidCallback onApprove;

  const _KnockRequestRow({
    required this.user,
    required this.room,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final displayname = user.localizedDisplayname(l10n);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        children: [
          MergeSemantics(
            child: Semantics(
              label: displayname,
              child: Builder(
                builder: (avatarContext) => InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => showMemberActionsPopupMenu(
                    context: avatarContext,
                    user: user,
                    room: room,
                  ),
                  child: ExcludeSemantics(
                    child: Avatar(
                      mxContent: user.avatarUrl,
                      name: displayname,
                      size: 34.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  l10n.knocking,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: onApprove,
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(l10n.approve, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/course_avatar.dart';
import 'package:fluffychat/pangea/common/widgets/invited_chip.dart';
import 'package:fluffychat/pangea/common/widgets/role_badge.dart';
import 'package:fluffychat/pangea/common/widgets/roving_focus_group.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/routes/courses/course_members_chip.dart';

class AddCourseTile extends StatelessWidget {
  final AddCourseTileContent content;
  final VoidCallback? onTap;
  final bool expanded;

  /// Someone is knocking on this course and the viewer is an admin who can act
  /// on it — the avatar wears the red "!" badge, outranking the course-ping
  /// bell. Supplied by [AddCourseTileList], which watches the member list.
  final bool hasKnockingUsers;

  /// Max title lines before ellipsizing. The course preview's minimized header
  /// passes 1 — a wrapped title can overflow the short sheet (#7826).
  final int titleMaxLines;

  /// This tile's id in the enclosing [RovingFocusGroup]: a course list is one
  /// Tab stop, with the arrow keys moving between its tiles. Null for a tile
  /// outside a group.
  final String? rovingId;

  const AddCourseTile({
    super.key,
    required this.content,
    this.onTap,
    this.expanded = false,
    this.hasKnockingUsers = false,
    this.titleMaxLines = 2,
    this.rovingId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final courseId = content.courseId;
    final members = content.members;
    final invited = content.invited ?? false;
    final unreadCoursePingEvent = content.unreadCoursePingEvent;
    final courseChildrenIds = content.courseChildrenIds;
    final title = content.title(L10n.of(context));
    final expandedContent = content.expandedContent;

    // An invited course hides its member/level chips, so the participant count
    // would announce detail that isn't on screen — lead with the state instead.
    final courseLabel = invited
        ? '$title, ${L10n.of(context).invited}'
        : members != null
        ? '$title, ${L10n.of(context).countParticipants(members)}'
        : title;

    // The Admin label and the knock badge sit inside the tile's own labeled
    // button node, so their state rides the tile label as well — the same way
    // `invited` does — rather than relying on the nested node being announced.
    final label = [
      courseLabel,
      if (content.isAdmin) L10n.of(context).admin,
      if (hasKnockingUsers) L10n.of(context).aUserIsKnocking,
    ].join(', ');

    final Widget? chips = invited
        ? ExcludeSemantics(child: InvitedChip())
        : courseId != null
        ? CourseInfoChips(
            courseId,
            courseRoomId: content.courseRoomId,
            members: members,
            fontSize: 12.0,
            iconSize: 12.0,
          )
        : members != null
        ? CourseMembersChip(members, fontSize: 12.0, iconSize: 12.0)
        : null;

    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        button: onTap != null,
        label: label,
        child: InkWell(
          onTap: onTap,
          focusNode: rovingId == null
              ? null
              : RovingFocusGroup.nodeOf(context, rovingId!),
          borderRadius: BorderRadius.circular(12.0),
          child: Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.0),
              border: onTap != null
                  ? Border.all(color: theme.colorScheme.primary)
                  : null,
            ),
            child: Column(
              spacing: 12.0,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  spacing: 12.0,
                  children: [
                    CourseAvatar(
                      avatar: content.imageUrl,
                      displayname: title,
                      size: 48.0,
                      unreadCoursePingEvent: unreadCoursePingEvent,
                      courseChildrenIds: courseChildrenIds,
                      invite: invited,
                      hasKnockingUsers: hasKnockingUsers,
                    ),
                    Expanded(
                      child: Column(
                        spacing: 6.0,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: .spaceBetween,
                            children: [
                              Expanded(
                                child: ExcludeSemantics(
                                  child: Text(
                                    title,
                                    style: theme.textTheme.bodyLarge,
                                    maxLines: titleMaxLines,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              if (content.isKnock)
                                Padding(
                                  padding: .only(left: 8),
                                  child: Tooltip(
                                    message: L10n.of(context).restricted,
                                    child: Icon(Icons.lock_outlined, size: 18),
                                  ),
                                ),
                            ],
                          ),
                          // The Admin label holds the tile's bottom-right
                          // corner; the chips wrap beside it, never under it.
                          if (content.isAdmin)
                            Row(
                              spacing: 8.0,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(child: chips ?? const SizedBox()),
                                const ExcludeSemantics(
                                  child: RoleBadge(RoleBadgeType.admin),
                                ),
                              ],
                            )
                          else
                            ?chips,
                        ],
                      ),
                    ),
                  ],
                ),
                if (expanded && expandedContent != null)
                  Text(expandedContent, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

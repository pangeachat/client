import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/course_avatar.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';

class AddCourseTile extends StatelessWidget {
  final AddCourseTileContent content;
  final VoidCallback? onTap;
  final bool expanded;

  const AddCourseTile({
    super.key,
    required this.content,
    this.onTap,
    this.expanded = false,
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
    final label = invited
        ? '$title, ${L10n.of(context).invited}'
        : members != null
        ? '$title, ${L10n.of(context).countParticipants(members)}'
        : title;

    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
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
                                    maxLines: 2,
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
                          Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (invited)
                                ExcludeSemantics(
                                  child: CourseInfoChip(
                                    icon: Icons.mail,
                                    text: L10n.of(context).invited,
                                    fontSize: 12.0,
                                    iconSize: 12.0,
                                    highlightColor: AppConfig.goldByTheme(
                                      context,
                                    ),
                                    foregroundColor: AppConfig.onGoldByTheme(
                                      context,
                                    ),
                                  ),
                                ),
                              if (members != null && !invited)
                                Semantics(
                                  label: L10n.of(
                                    context,
                                  ).countParticipants(members),
                                  child: ExcludeSemantics(
                                    child: CourseInfoChip(
                                      icon: Icons.group,
                                      text: '$members',
                                      fontSize: 12.0,
                                      iconSize: 12.0,
                                    ),
                                  ),
                                ),
                              if (courseId != null && !invited)
                                CourseInfoChips(
                                  courseId,
                                  courseRoomId: content.courseRoomId,
                                  fontSize: 12.0,
                                  iconSize: 12.0,
                                ),
                            ],
                          ),
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

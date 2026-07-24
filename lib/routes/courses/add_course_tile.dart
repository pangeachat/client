import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

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
    final title = content.title(L10n.of(context));
    final expandedContent = content.expandedContent;

    final label = members != null
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
                    ExcludeSemantics(
                      child: SizedBox(
                        width: 48.0,
                        height: 48.0,
                        child: ImageByUrl(
                          imageUrl: content.imageUrl,
                          width: 48.0,
                          borderRadius: BorderRadius.circular(10.0),
                          replacement: Avatar(
                            name: title,
                            borderRadius: BorderRadius.circular(10.0),
                            size: 48.0,
                          ),
                        ),
                      ),
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
                              if (members != null)
                                CourseInfoChip(
                                  icon: Icons.group,
                                  text: '$members',
                                  fontSize: 12.0,
                                  iconSize: 12.0,
                                ),
                              if (courseId != null)
                                CourseInfoChips(
                                  courseId,
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

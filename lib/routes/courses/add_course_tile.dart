import 'package:flutter/material.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

class AddCourseTile extends StatelessWidget {
  final PublicCoursesChunk? chunk;
  final CoursePlanModel coursePlan;
  final Function() onTap;
  final bool isKnock;

  const AddCourseTile({
    super.key,
    this.chunk,
    required this.coursePlan,
    required this.onTap,
    this.isKnock = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final course = chunk?.room;
    final displayname =
        course?.name ?? course?.canonicalAlias ?? coursePlan.title;

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: InkWell(
          onTap: () => onTap(),
          borderRadius: BorderRadius.circular(12.0),
          child: Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: theme.colorScheme.primary),
            ),
            child: Row(
              spacing: 12.0,
              children: [
                SizedBox(
                  width: 48.0,
                  height: 48.0,
                  child: ImageByUrl(
                    imageUrl: coursePlan.imageUrl,
                    width: 48.0,
                    borderRadius: BorderRadius.circular(10.0),
                    replacement: Avatar(
                      name: coursePlan.title,
                      borderRadius: BorderRadius.circular(10.0),
                      size: 48.0,
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
                            child: Text(
                              displayname,
                              style: theme.textTheme.bodyLarge,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isKnock)
                            Padding(
                              padding: .only(left: 8),
                              child: Tooltip(
                                message: L10n.of(context).restricted,
                                child: Icon(Icons.lock_outlined, size: 18),
                              ),
                            ),
                        ],
                      ),
                      CourseInfoChips(
                        coursePlan.uuid,
                        iconSize: 12.0,
                        fontSize: 12.0,
                      ),
                    ],
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

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

class AddCourseTileByRoom extends StatelessWidget {
  final Room space;
  final VoidCallback onTap;
  const AddCourseTileByRoom(this.space, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _AddCourseTile(
      title: space.getLocalizedDisplayname(),
      onTap: onTap,
      imageUrl: space.avatar,
      members: space.summary.mJoinedMemberCount ?? 1,
      courseId: space.coursePlan?.uuid,
    );
  }
}

class AddCourseTileByPreview extends StatelessWidget {
  final PublicCoursesChunk preview;
  final VoidCallback onTap;
  const AddCourseTileByPreview(this.preview, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _AddCourseTile(
      title:
          preview.room.name ??
          preview.room.canonicalAlias ??
          L10n.of(context).course,
      imageUrl: preview.room.avatarUrl,
      onTap: onTap,
      members: preview.room.numJoinedMembers,
      courseId: preview.courseId,
      isKnock: preview.room.joinRule == JoinRules.knock.name,
    );
  }
}

class AddCourseTileByCourse extends StatelessWidget {
  final CoursePlanModel course;
  final VoidCallback onTap;
  const AddCourseTileByCourse(this.course, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _AddCourseTile(
      title: course.title,
      courseId: course.uuid,
      onTap: onTap,
    );
  }
}

class _AddCourseTile extends StatelessWidget {
  final String title;
  final Function() onTap;

  final Uri? imageUrl;
  final int? members;

  final String? courseId;
  final bool isKnock;

  const _AddCourseTile({
    required this.title,
    required this.onTap,
    this.imageUrl,
    this.members,
    this.courseId,
    this.isKnock = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final courseId = this.courseId;
    final members = this.members;

    final label = members != null
        ? '$title, ${L10n.of(context).countParticipants(members)}'
        : title;

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Semantics(
          button: true,
          label: label,
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
                  ExcludeSemantics(
                    child: SizedBox(
                      width: 48.0,
                      height: 48.0,
                      child: ImageByUrl(
                        imageUrl: imageUrl,
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
            ),
          ),
        ),
      ),
    );
  }
}

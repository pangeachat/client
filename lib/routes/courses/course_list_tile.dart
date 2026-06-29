import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// A single joined-course row in the Courses panel: the course's image, name,
/// and a meta row of chips (participants, plus language / level / modules once
/// the course plan loads). Tapping it opens that course in the workspace via the
/// `?m=course:<id>` filter + `course` panel. Modeled on the public-course card
/// in find_course_page.dart. Image / name / participant count are read straight
/// off the synced [Room] (no network); the plan-derived chips hydrate via
/// [CourseInfoChips], which self-manages its async load. See
/// routing.instructions.md.
class CourseListTile extends StatelessWidget {
  final Room space;

  const CourseListTile(this.space, {super.key});

  void _open(BuildContext context) {
    // No tab param — open the course card on its default tab, same as tapping the
    // course in the rail (a tab arg would emit a redundant `course:course` token).
    context.go(
      WorkspaceNav.openCourseFilter(GoRouterState.of(context).uri, space.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final displayname = space.getLocalizedDisplayname(MatrixLocals(l10n));
    // Participant count comes straight off the synced room summary — no network.
    final members = space.summary.mJoinedMemberCount ?? 1;
    final courseId = space.coursePlan?.uuid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Semantics(
        button: true,
        label: '$displayname, $members ${l10n.participants}',
        child: Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12.0),
          child: InkWell(
            onTap: () => _open(context),
            borderRadius: BorderRadius.circular(12.0),
            child: Container(
              padding: const EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Avatar(
                      mxContent: space.avatar,
                      name: displayname,
                      size: 44.0,
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Text(
                            displayname,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8.0),
                        Wrap(
                          spacing: 12.0,
                          runSpacing: 6.0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            CourseInfoChip(
                              icon: Icons.group,
                              text: '$members',
                              fontSize: 12.0,
                              iconSize: 14.0,
                            ),
                            // Language / level / modules hydrate once the course
                            // plan loads (CourseInfoChips shows nothing until
                            // ready).
                            if (courseId != null)
                              CourseInfoChips(
                                courseId,
                                fontSize: 12.0,
                                iconSize: 14.0,
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

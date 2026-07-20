import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/add_course_options.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/add_course_tile_list.dart';
import 'package:fluffychat/routes/world/panel_header.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The courses the learner is in — spaces they've joined that carry a course
/// plan — sorted by localized display name. Shared so the panel body and the
/// shell's content-fit height estimate count exactly the same rooms.
List<Room> joinedCourses(Client client, L10n l10n) =>
    client.rooms
        .where(
          (r) =>
              r.isSpace &&
              r.membership == Membership.join &&
              r.coursePlan != null,
        )
        .toList()
      ..sort(
        (a, b) => a
            .getLocalizedDisplayname(MatrixLocals(l10n))
            .toLowerCase()
            .compareTo(
              b.getLocalizedDisplayname(MatrixLocals(l10n)).toLowerCase(),
            ),
      );

/// The **Courses** left-column panel (world_v2): the "Courses" header plus the
/// scrollable list of joined courses.
///
/// The three add-course actions (start my own / enter a code / browse public)
/// live in the header as compact right-justified icons once the learner has at
/// least one course — so the list gets the vertical space — and drop to
/// full-width buttons in the body as the empty state when the learner is in no
/// courses yet. The panel host ([WorkspaceLeftPanel]) supplies the surrounding
/// card chrome (or, on narrow, the nav-widget cavity). See routing.instructions.md.
class CoursesHubPanel extends StatelessWidget {
  final Widget closeButton;

  const CoursesHubPanel({super.key, required this.closeButton});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final l10n = L10n.of(context);

    return StreamBuilder(
      stream: client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) {
        final courses = joinedCourses(client, l10n);
        return Column(
          children: [
            PanelHeader(
              leading: closeButton,
              title: l10n.courses,
              // With courses present, the three add-course actions ride the
              // header as right-justified icons; when empty they stay as full
              // buttons in the body below (the empty state).
              trailing: courses.isEmpty ? null : const AddCourseHeaderActions(),
            ),
            Expanded(child: LeftPanelCoursesListView(courses: courses)),
          ],
        );
      },
    );
  }
}

/// The scrollable body of [CoursesHubPanel]: a tile per joined course, and —
/// only when the learner has none yet — the "Add new course" divider and the
/// full-width add-course buttons as the empty state (#7172: an empty list isn't
/// a plan-less course, so no "needs a plan" message here).
class LeftPanelCoursesListView extends StatelessWidget {
  final List<Room> courses;

  const LeftPanelCoursesListView({super.key, required this.courses});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return AddCourseTileList(
      padding: const EdgeInsets.fromLTRB(12.0, 4.0, 12.0, 16.0),
      content: courses.map((c) => RoomAddCourseTileContent(c)).toList(),
      onTap: (index) => context.go(
        WorkspaceNav.openCourse(
          GoRouterState.of(context).uri,
          courses[index].id,
        ),
      ),
      extraContent: courses.isEmpty
          ? [
              const SizedBox(height: 4.0),
              // "Add new course" section divider + the full add-course buttons.
              Row(
                children: [
                  Expanded(
                    child: Divider(color: theme.colorScheme.outlineVariant),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(
                      l10n.addNewCourse,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(color: theme.colorScheme.outlineVariant),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),
              const AddCourseOptions(),
            ]
          : null,
    );
  }
}

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/add_course_options.dart';
import 'package:fluffychat/routes/courses/course_list_tile.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The body of the **Courses** left-column panel (world_v2): the courses the
/// user is in, listed as tiles, followed by the add-course options (start my
/// own / enter a code / browse public). Replaces the old float-over-the-map
/// "Add new course" hub card, which double-wrapped a card inside the panel's own
/// PanelCard. The panel host ([WorkspaceLeftPanel]) supplies the surrounding
/// card chrome and the "Courses" header + close control, so this is just the
/// scrollable content. See routing.instructions.md.
class CoursesPanelView extends StatelessWidget {
  const CoursesPanelView({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return StreamBuilder(
      stream: client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) {
        final courses = client.rooms
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

        return ListView(
          padding: const EdgeInsets.fromLTRB(12.0, 4.0, 12.0, 16.0),
          children: [
            for (final space in courses) CourseListTile(space),
            if (courses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  l10n.noCourseFound,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 4.0),
            // "Add new course" section divider + the add options.
            Row(
              children: [
                Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text(
                    l10n.addNewCourse,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
              ],
            ),
            const SizedBox(height: 12.0),
            const AddCourseOptions(),
          ],
        );
      },
    );
  }
}

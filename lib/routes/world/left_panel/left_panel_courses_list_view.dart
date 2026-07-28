import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/routes/courses/add_course_options.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/add_course_tile_list.dart';
import 'package:fluffychat/routes/world/panel_header.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

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
        final courses = client.sortedCourses(l10n);
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

/// The scrollable body of [CoursesHubPanel]: a tile per invited or joined
/// course (matching nav rail behavior on course selection), and — only when the
/// learner has none yet — the "Add new course" divider and the full-width
/// add-course buttons as the empty state (#7172).
class LeftPanelCoursesListView extends StatelessWidget {
  final List<Room> courses;

  const LeftPanelCoursesListView({super.key, required this.courses});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: AddCourseTileList(
        content: courses.map((c) => RoomAddCourseTileContent(c)).toList(),
        onTap: (index) =>
            Matrix.of(context).client.onTapCourse(context, courses[index]),
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
      ),
    );
  }
}

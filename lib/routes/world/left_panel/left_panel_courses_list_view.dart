import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/add_course_options.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/add_course_tile_list.dart';
import 'package:fluffychat/routes/world/panel_header.dart';
import 'package:fluffychat/utils/chat_list_handle_space_tap.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Sort invited courses to the top of the course list
/// Courses within categories are sorted by localized display name.
List<Room> sortedCourses(Client client, L10n l10n) =>
    client.rooms
        .where(
          (r) =>
              r.isSpace &
              (r.membership == Membership.join ||
                  r.membership == Membership.invite),
        )
        .toList()
      ..sort((a, b) {
        if (priority(a) != priority(b)) {
          return priority(a).compareTo(priority(b));
        }
        return a
            .getLocalizedDisplayname(MatrixLocals(l10n))
            .toLowerCase()
            .compareTo(
              b.getLocalizedDisplayname(MatrixLocals(l10n)).toLowerCase(),
            );
      });

int priority(Room room) => room.membership == Membership.invite ? 1 : 2;

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
        final courses = sortedCourses(client, l10n);
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

/// The scrollable body of [CoursesHubPanel],
/// containing a tile for each invited or joined course.
/// Matches nav rail course behavior on course selection.
class LeftPanelCoursesListView extends StatelessWidget {
  final List<Room> courses;

  const LeftPanelCoursesListView({super.key, required this.courses});

  // Open joined courses, or open popup for invited courses
  Future<void> _onTapCourse(BuildContext context, Room course) async {
    final uri = GoRouterState.of(context).uri;
    final client = Matrix.of(context).client;
    final membership = course.membership;

    if (!{Membership.invite, Membership.leave}.contains(membership)) {
      context.go(
        WorkspaceNav.openCourseSection(uri, course.id, keepRoom: false),
      );
      return;
    }

    final joinResp = course.membership == Membership.invite
        ? await SpaceTapUtil.onInviteTap(context, course)
        : await SpaceTapUtil.autoJoin(context, course);

    if (joinResp == null) return;
    final joinedRoom = client.getRoomById(joinResp.roomId);
    if (joinedRoom == null) return;

    final handler = JoinRoomAnalyticsConsentHandler(joinResp, joinedRoom);
    final joinedRoomId = await handler.handle(context);
    if (joinedRoomId == null) return;

    context.go(
      WorkspaceNav.openCourseSection(uri, joinedRoomId, keepRoom: false),
    );
    return;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: AddCourseTileList(
        content: courses.map((c) => RoomAddCourseTileContent(c)).toList(),
        onTap: (index) => _onTapCourse(context, courses[index]),
      ),
    );
  }
}

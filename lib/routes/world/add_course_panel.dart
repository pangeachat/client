import 'package:flutter/material.dart';

import 'package:fluffychat/features/course_plans/new_course_page.dart';
import 'package:fluffychat/routes/courses/find_course_page.dart';
import 'package:fluffychat/routes/courses/private/course_code_page.dart';
import 'package:fluffychat/routes/world/courses_panel_view.dart';

/// The body of the left-column **add-course panel** (world_v2): the add-course
/// wizard, hosted as a URL-token panel instead of the retired route-driven
/// `_MainView` card. The step is the `addcourse` token's param — a **bare**
/// token (no param) is the hub chooser (the entry the rail "+" opens), `own`
/// (start my own / plan list), `browse` (public courses), or `private` (enter a
/// code). Each hosted page carries its own header/close; the deeper steps
/// (`/courses/own/:courseid` …) stay route-driven detail. See
/// `routing.instructions.md`.
class AddCoursePanel extends StatelessWidget {
  /// The wizard step from the token param: null (the hub), `own`, `browse`, or
  /// `private`.
  final String? subPath;

  /// The current URL, so the plan list can read its `lang`/`showAll` filters.
  final Uri currentUri;

  const AddCoursePanel({super.key, this.subPath, required this.currentUri});

  @override
  Widget build(BuildContext context) {
    switch (subPath) {
      case 'browse':
        return const FindCoursePage();
      case 'private':
        return const CourseCodePage();
      case 'own':
        return NewCoursePage(
          route: 'rooms',
          initialLanguageCode: currentUri.queryParameters['lang'],
          showAll: currentUri.queryParameters['showAll'] == 'true',
        );
      default:
        // A bare `addcourse` token is the Courses panel. It is normally
        // rendered by the panel host with a "Courses" header + close; this is a
        // headerless fallback for any direct use. See CoursesPanelView.
        return const CoursesPanelView();
    }
  }
}

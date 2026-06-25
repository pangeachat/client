import 'package:flutter/material.dart';

import 'package:fluffychat/features/course_plans/new_course_page.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/find_course_page.dart';
import 'package:fluffychat/routes/courses/private/course_code_page.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_close_button.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_courses_list_view.dart';
import 'package:fluffychat/routes/world/panel_header.dart';

/// The body of the left-column **add-course panel** (world_v2): the add-course
/// wizard, hosted as a URL-token panel instead of the retired route-driven
/// `_MainView` card. The step is the `addcourse` token's param — a **bare**
/// token (no param) is the hub chooser (the entry the rail "+" opens), `own`
/// (start my own / plan list), `browse` (public courses), or `private` (enter a
/// code). Each hosted page carries its own header/close; the deeper steps
/// (`/courses/own/:courseid` …) stay route-driven detail. See
/// `routing.instructions.md`.
class LeftPanelAddCourseSubpage extends StatelessWidget {
  final PanelToken token;
  final Uri currentUri;
  final bool foldedOver;
  final bool isColumnMode;

  const LeftPanelAddCourseSubpage({
    super.key,
    required this.token,
    required this.currentUri,
    required this.foldedOver,
    required this.isColumnMode,
  });

  @override
  Widget build(BuildContext context) {
    switch (token.param) {
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
        return Column(
          children: [
            PanelHeader(
              leading: LeftPanelCloseButton(
                token: token,
                currentUri: currentUri,
                foldedOver: foldedOver,
                isColumnMode: isColumnMode,
              ),
              title: L10n.of(context).courses,
            ),
            Expanded(child: LeftPanelCoursesListView()),
          ],
        );
    }
  }
}

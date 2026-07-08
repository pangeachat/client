import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/features/course_plans/new_course_page.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/find_course_page.dart';
import 'package:fluffychat/routes/courses/own/invite/course_invite_page.dart';
import 'package:fluffychat/routes/courses/own/selected_course_page.dart';
import 'package:fluffychat/routes/courses/preview/public_course_preview.dart';
import 'package:fluffychat/routes/courses/private/course_code_page.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_courses_list_view.dart';
import 'package:fluffychat/routes/world/panel_header.dart';

/// The body of the left-column **add-course panel** (world_v2): the add-course
/// wizard, hosted as a URL-token panel instead of the retired route-driven
/// `_MainView` card. The step is the `addcourse` token's param — a **bare**
/// token (no param) is the hub chooser (the entry the rail "+" opens), `browse`
/// (public courses), `private[/<code>]` (enter a code; an inbound join link's
/// code rides the leaf and submits itself), or `own[/<lang>|/all]` (start my
/// own / plan list): a trailing language code seeds the picker's language
/// filter, `all` means no filter (showAll) — folded into the token instead of
/// loose `?lang=`/`?showAll=` query params (routing.instructions.md). Each
/// hosted page carries its own header/close; the deeper steps
/// (`/courses/own/:courseid` …) stay route-driven detail.
class LeftPanelAddCourseSubpage extends StatelessWidget {
  final AddCourseTokenParam? param;
  final Widget closeButton;
  final Completer<String>? courseCreationCompleter;

  const LeftPanelAddCourseSubpage({
    super.key,
    required this.param,
    required this.closeButton,
    this.courseCreationCompleter,
  });

  @override
  Widget build(BuildContext context) {
    switch (param?.subpage) {
      case 'browse':
        final roomId = param?.roomId;
        if (roomId != null) {
          return PublicCoursePreview(roomID: roomId);
        }
        return const FindCoursePage();
      case 'private':
        return CourseCodePage(initialCode: param?.joinCode);
      case 'own':
        final courseId = param?.courseId;
        if (courseId != null) {
          if (param?.invite == true) {
            return CourseInvitePage(
              courseId,
              courseCreationCompleter: courseCreationCompleter,
            );
          }
          return SelectedCourse(courseId, SelectedCourseMode.launch);
        }
        return NewCoursePage(
          route: 'rooms',
          initialLanguageCode: param?.targetLanguage,
          showAll: param?.targetLanguage == 'all',
        );
      default:
        return Column(
          children: [
            PanelHeader(leading: closeButton, title: L10n.of(context).courses),
            Expanded(child: LeftPanelCoursesListView()),
          ],
        );
    }
  }
}

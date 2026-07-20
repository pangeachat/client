import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/features/course_plans/new_course_page.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/routes/courses/find_course_page.dart';
import 'package:fluffychat/routes/courses/own/invite/course_invite_page.dart';
import 'package:fluffychat/routes/courses/own/selected_course_page.dart';
import 'package:fluffychat/routes/courses/preview/public_course_preview.dart';
import 'package:fluffychat/routes/courses/private/course_code_page.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_courses_list_view.dart';

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
  final AddCoursePageTokenParam? param;
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
    final param = this.param;
    if (param == null) {
      return CoursesHubPanel(closeButton: closeButton);
    }

    switch (param.subpage) {
      case AddCourseSubpageEnum.browse:
        final roomId = param.previewRoomId;
        if (roomId != null) {
          // previewRoomId rides the URL token as a bare localpart (shortRoomId
          // on encode); re-attach the home server_name at this read-back
          // boundary so join/knock get a legal room id — mirrors routes.dart's
          // `preview/:courseroomid` builder. See room_id_url.dart.
          return PublicCoursePreview(
            roomID: fullRoomId(roomId),
            closeButton: closeButton,
          );
        }
        return FindCoursePage(
          closeButton: closeButton,
          initialLanguageCode: param.initialLanguageFilter,
          showAll: param.allLanguagesFilter,
        );
      case AddCourseSubpageEnum.private:
        return CourseCodePage(
          initialCode: param.privateCourseJoinCode,
          closeButton: closeButton,
        );
      case AddCourseSubpageEnum.own:
        final courseId = param.createCourseId;
        if (courseId != null) {
          if (param.showNewCourseInvitePage == true) {
            return CourseInvitePage(
              courseId,
              courseCreationCompleter: courseCreationCompleter,
            );
          }
          return SelectedCourse(
            courseId,
            SelectedCourseMode.launch,
            closeButton: closeButton,
          );
        }
        return NewCoursePage(
          route: 'rooms',
          initialLanguageCode: param.initialLanguageFilter,
          showAll: param.allLanguagesFilter,
          closeButton: closeButton,
        );
    }
  }
}

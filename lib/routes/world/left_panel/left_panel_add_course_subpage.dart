import 'package:flutter/material.dart';

import 'package:fluffychat/features/course_plans/new_course_page.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/find_course_page.dart';
import 'package:fluffychat/routes/courses/private/course_code_page.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_close_button.dart';
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
    final param = token.param ?? '';
    if (param == 'browse') return const FindCoursePage();
    if (param == 'private' || param.startsWith('private/')) {
      // An inbound join link's code rides as a `private/<code>` leaf
      // (LegacyRedirects, #7524): the join-with-code page prefills it and
      // submits the same join a manual entry performs.
      final field = param.startsWith('private/')
          ? param.substring('private/'.length)
          : null;
      return CourseCodePage(
        initialCode: field == null || field.isEmpty
            ? null
            : TokenFields.decode(field),
      );
    }
    if (param == 'own' || param.startsWith('own/')) {
      final field = param.startsWith('own/')
          ? param.substring('own/'.length)
          : null;
      return NewCoursePage(
        route: 'rooms',
        initialLanguageCode: field == null || field == 'all'
            ? null
            : TokenFields.decode(field),
        showAll: field == 'all',
      );
    }
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

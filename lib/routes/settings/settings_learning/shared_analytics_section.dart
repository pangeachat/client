import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/analytics_sharing_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/course_avatar.dart';
import 'package:fluffychat/routes/settings/settings_learning/settings_section_header.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The courses whose teachers can see the learner's progress, which the
/// snackbar on joining a course links to. Each opens its course; there is no
/// control here, since leaving a course stops the sharing
/// (course-analytics-access.instructions.md).
class SharedAnalyticsSection extends StatefulWidget {
  const SharedAnalyticsSection({super.key});

  @override
  State<SharedAnalyticsSection> createState() => _SharedAnalyticsSectionState();
}

class _SharedAnalyticsSectionState extends State<SharedAnalyticsSection> {
  late final Future<List<Room>> _courses = _load();

  Future<List<Room>> _load() async {
    try {
      return await Matrix.of(context).client.coursesSharingAnalytics();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {},
        level: PangeaHttpException.severityOf(e),
      );
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      children: [
        SettingsSectionHeader(title: l10n.sharedAnalyticsTitle),
        ListTile(subtitle: Text(l10n.sharedAnalyticsDesc)),
        FutureBuilder<List<Room>>(
          future: _courses,
          builder: (context, snapshot) {
            // A failed read shows nothing rather than an empty list, which
            // would claim the learner shares with no course.
            if (snapshot.hasError) return const SizedBox.shrink();
            final courses = snapshot.data;
            if (courses == null) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator.adaptive(),
              );
            }
            if (courses.isEmpty) {
              return ListTile(subtitle: Text(l10n.sharedAnalyticsNone));
            }
            return Column(
              children: [
                for (final course in courses) SharedCourseTile(course: course),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One shared course: its avatar and name, opening the course's page.
class SharedCourseTile extends StatelessWidget {
  final Room course;

  const SharedCourseTile({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final name = course.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    return ListTile(
      leading: CourseAvatar(
        avatar: course.avatar,
        courseId: course.coursePlan?.uuid,
        displayname: name,
        size: 40.0,
      ),
      title: Text(name),
      onTap: () => context.go(
        WorkspaceNav.openCourse(GoRouterState.of(context).uri, course.id),
      ),
    );
  }
}

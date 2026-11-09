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
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Who can see the learner's progress, which the snackbar on joining a course
/// links to: each course, opening its page, with its teachers who can, then
/// everyone else who can, whom the learner may remove. A course's teachers
/// cannot be removed here; leaving the course does that
/// (course-analytics-access.instructions.md).
class SharedAnalyticsSection extends StatefulWidget {
  const SharedAnalyticsSection({super.key});

  @override
  State<SharedAnalyticsSection> createState() => _SharedAnalyticsSectionState();
}

class _SharedAnalyticsSectionState extends State<SharedAnalyticsSection> {
  late Future<AnalyticsSharing> _sharing = _load();

  Future<AnalyticsSharing> _load() async {
    try {
      return await Matrix.of(context).client.analyticsSharing();
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

  Future<void> _remove(User viewer) async {
    final l10n = L10n.of(context);
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: l10n.areYouSure,
      message: l10n.removeAnalyticsAccessDesc(viewer.calcDisplayname()),
      okLabel: l10n.remove,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (confirmed != OkCancelResult.ok || !mounted) return;
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.removeAnalyticsViewer(viewer.id),
    );
    if (result.isError || !mounted) return;
    setState(() => _sharing = _load());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      children: [
        SettingsSectionHeader(title: l10n.sharedAnalyticsTitle),
        ListTile(subtitle: Text(l10n.sharedAnalyticsDesc)),
        FutureBuilder<AnalyticsSharing>(
          future: _sharing,
          builder: (context, snapshot) {
            // A failed read shows nothing rather than an empty list, which
            // would claim the learner shares with no one.
            if (snapshot.hasError) return const SizedBox.shrink();
            final sharing = snapshot.data;
            if (sharing == null) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator.adaptive(),
              );
            }
            if (sharing.isEmpty) {
              return ListTile(subtitle: Text(l10n.sharedAnalyticsNone));
            }
            return Column(
              children: [
                for (final shared in sharing.courses)
                  SharedCourseTile(shared: shared),
                if (sharing.others.isNotEmpty) ...[
                  ListTile(subtitle: Text(l10n.sharedAnalyticsOthersTitle)),
                  for (final viewer in sharing.others)
                    ListTile(
                      leading: Avatar(
                        mxContent: viewer.avatarUrl,
                        name: viewer.calcDisplayname(),
                      ),
                      title: Text(viewer.calcDisplayname()),
                      trailing: IconButton(
                        icon: const Icon(Icons.person_remove_outlined),
                        tooltip: l10n.removeAnalyticsAccess,
                        onPressed: () => _remove(viewer),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One shared course: its avatar and name, opening the course's page, with
/// its teachers who can see the learner's progress listed under the name.
class SharedCourseTile extends StatelessWidget {
  final SharedCourse shared;

  const SharedCourseTile({super.key, required this.shared});

  @override
  Widget build(BuildContext context) {
    final course = shared.course;
    final name = course.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    return ListTile(
      leading: CourseAvatar(
        avatar: course.avatar,
        courseId: course.coursePlan?.uuid,
        displayname: name,
        size: 40.0,
      ),
      title: Text(name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4.0,
        children: [
          for (final teacher in shared.teachers)
            Row(
              spacing: 8.0,
              children: [
                Avatar(
                  mxContent: teacher.avatarUrl,
                  name: teacher.calcDisplayname(),
                  size: 24.0,
                ),
                Flexible(child: Text(teacher.calcDisplayname())),
              ],
            ),
        ],
      ),
      onTap: () => context.go(
        WorkspaceNav.openCourse(GoRouterState.of(context).uri, course.id),
      ),
    );
  }
}

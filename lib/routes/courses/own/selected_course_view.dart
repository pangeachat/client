import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/courses/add_course_tile.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SelectedCourseView extends StatelessWidget {
  final Widget? closeButton;
  final String title;

  final RoomSummaryResponse? summary;
  final CoursePlanModel? course;
  final AddCourseTileContent? content;
  final bool loading;
  final bool hasError;
  final VoidCallback onTapCta;
  final String ctaButtonText;

  const SelectedCourseView({
    super.key,
    this.closeButton,
    required this.title,
    this.summary,
    this.course,
    this.content,
    this.loading = false,
    this.hasError = false,
    required this.onTapCta,
    required this.ctaButtonText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: closeButton,
        title: Text(
          title,
          style: FluffyThemes.isColumnMode(context)
              ? theme.textTheme.titleLarge
              : theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Builder(
                builder: (context) {
                  final course = this.course;
                  final summary = this.summary;
                  final hasError = this.hasError;
                  final loading = this.loading;
                  final content = this.content;

                  if (loading) {
                    return const Center(
                      child: CircularProgressIndicator.adaptive(),
                    );
                  }

                  if (hasError || course == null) {
                    return Center(
                      child: ErrorIndicator(
                        message: L10n.of(context).oopsSomethingWentWrong,
                      ),
                    );
                  }

                  final adminIds = summary?.adminUserIDs ?? [];
                  return Column(
                    spacing: 20.0,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: onTapCta,
                          label: Text(ctaButtonText),
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            foregroundColor:
                                theme.colorScheme.onPrimaryContainer,
                            padding: const EdgeInsets.symmetric(vertical: 14.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                          ),
                        ),
                      ),
                      if (content != null)
                        AddCourseTile(content: content, expanded: true),
                      if (adminIds.isNotEmpty) _CourseAdminDisplay(adminIds),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CourseAdminDisplay extends StatelessWidget {
  final List<String> adminIds;
  const _CourseAdminDisplay(this.adminIds);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: theme.colorScheme.primary),
      ),
      child: Column(
        children: [
          ...adminIds.map(
            (id) => FutureBuilder(
              future: Matrix.of(context).client.getProfileFromUserId(id),
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final displayName = profile?.displayName ?? id.localpart ?? id;
                return InkWell(
                  onTap: profile != null
                      ? () => UserDialog.show(
                          context: context,
                          profile: profile,
                          uri: GoRouterState.of(context).uri,
                        )
                      : null,
                  child: Row(
                    spacing: 8.0,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Avatar(
                        size: 40.0,
                        mxContent: profile?.avatarUrl,
                        name: displayName,
                        userId: id,
                      ),
                      Expanded(
                        child: Text(
                          displayName,
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

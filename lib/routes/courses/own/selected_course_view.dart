import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/courses/add_course_tile.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/course_cta_row.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Below this body height (header included) the view is COMPACT: a one-line
/// ellipsized header title, the CTA holding the bottom, and no scrollable
/// middle — the preview's minimized rest (#7826). Kept in step with the
/// shell's `_coursePreviewSheetMinimizedHeight`, the same pairing as the
/// activity sheet's `kActivityCompactMaxHeight`.
const double kCoursePreviewCompactMaxHeight = 220.0;

/// The course preview / selected-course page (#7826): the SAME tile the
/// learner tapped in the list pinned on top (back button to its left), the
/// join/create CTA row pinned at the bottom, and the description, admins, and
/// read-only modules list scrolling between. On the narrow sheet's minimized
/// rest the middle is dropped entirely (grow-before-scroll, like the activity
/// sheet).
class SelectedCourseView extends StatelessWidget {
  final Widget? closeButton;

  /// Fallback header text while the tile's content is still loading (or
  /// errored) — once [content] resolves, the tile is the header.
  final String title;

  final RoomSummaryResponse? summary;
  final CoursePlanModel? course;
  final AddCourseTileContent? content;
  final bool loading;
  final bool hasError;
  final VoidCallback onTapCta;
  final String ctaButtonText;

  /// Renders the course's Missions + activities (read-only) in the scrollable
  /// middle when supplied — the restored course-preview modules list (#7826).
  final QuestObjectivesLoader? objectivesProvider;

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
    this.objectivesProvider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final course = this.course;
    final content = this.content;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, bodyConstraints) {
          final compact =
              bodyConstraints.maxHeight < kCoursePreviewCompactMaxHeight;

          final header = Padding(
            padding: const EdgeInsets.fromLTRB(4.0, 4.0, 12.0, 0.0),
            child: Row(
              children: [
                ?closeButton,
                Expanded(
                  child: content != null
                      // A wrapped title can overflow the minimized sheet, so
                      // the compact header ellipsizes at one line; the tile's
                      // two-line default returns once expanded.
                      ? AddCourseTile(
                          content: content,
                          titleMaxLines: compact ? 1 : 2,
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(
                child: Builder(
                  builder: (context) {
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

                    final ctaRow = CourseCtaRow(
                      primary: CourseCtaAction(
                        label: ctaButtonText,
                        onPressed: onTapCta,
                      ),
                    );

                    // The minimized rest: nothing that scrolls, so an upward
                    // drag grows the sheet unopposed (grow-before-scroll).
                    if (compact) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [const Spacer(), ctaRow],
                        ),
                      );
                    }

                    final adminIds = summary?.adminUserIDs ?? [];
                    final objectivesProvider = this.objectivesProvider;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: Column(
                                spacing: 12.0,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // The header tile carries avatar/title/chips
                                  // — the middle starts at the description.
                                  if (course.description.isNotEmpty)
                                    Text(
                                      course.description,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  if (adminIds.isNotEmpty)
                                    _CourseAdminDisplay(adminIds),
                                  if (objectivesProvider != null) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Row(
                                        spacing: 8.0,
                                        children: [
                                          const Icon(
                                            Icons.map_outlined,
                                            size: 18.0,
                                          ),
                                          Text(
                                            L10n.of(context).coursePlan,
                                            style: theme.textTheme.titleMedium,
                                          ),
                                        ],
                                      ),
                                    ),
                                    CourseObjectivesList(
                                      questId: course.uuid,
                                      shrinkWrap: true,
                                      readOnly: true,
                                      objectivesProvider: objectivesProvider,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          // More air above the pinned CTA than below.
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 16.0,
                              bottom: 8.0,
                            ),
                            child: ctaRow,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
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

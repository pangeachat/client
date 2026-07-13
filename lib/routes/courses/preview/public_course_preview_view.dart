import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/map_clipper.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/courses/cefr_level_match.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';
import 'package:fluffychat/routes/courses/preview/public_course_preview.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

class PublicCoursePreviewView extends StatelessWidget {
  final PublicCoursePreviewController controller;
  const PublicCoursePreviewView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const double titleFontSize = 16.0;
    const double descFontSize = 12.0;

    const double largeIconSize = 24.0;
    const double smallIconSize = 12.0;

    return Scaffold(
      appBar: AppBar(
        // world_v2: explicit token-based back. The auto-implied back would pop
        // to the route-driven parent's blank EmptyPage (#7400); controller.back
        // returns to the browse-public list instead.
        leading: controller.widget.closeButton,
        title: Text(
          L10n.of(context).joinWithClassCode,
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
        child: Container(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500.0),
            child: ValueListenableBuilder(
              valueListenable: controller.objectivesProvider.questLoader,
              builder: (context, state, _) {
                if (controller.loading) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }

                if (controller.hasError) {
                  return Center(
                    child: ErrorIndicator(
                      message: L10n.of(context).oopsSomethingWentWrong,
                    ),
                  );
                }

                final course = controller.course!;
                final summary = controller.roomSummary!;

                final roomAvatar = summary.avatarUrl;
                final avatarUrl = roomAvatar != null
                    ? Uri.tryParse(roomAvatar)
                    : null;

                final displayname = summary.displayName ?? course.name;

                final userController =
                    MatrixState.pangeaController.userController;

                final cefrEntry = course.targetCefr;
                final courseCefr = cefrEntry != null
                    ? LanguageLevelTypeEnum.fromString(cefrEntry)
                    : null;

                final cefrMatch = courseCefr == null
                    ? CefrMatchResult.none
                    : computeCefrMatch(
                        context: context,
                        userLevel: userController.userCefrLevel,
                        courseLevel: courseCefr,
                        courseLanguage: course.targetLanguage,
                        userLanguage: userController.userL2Code,
                      );

                return Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 12.0,
                          left: 12.0,
                          right: 12.0,
                        ),
                        child: ListView.builder(
                          itemCount: 2,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Column(
                                spacing: 8.0,
                                children: [
                                  ClipPath(
                                    clipper: MapClipper(),
                                    child: ImageByUrl(
                                      imageUrl: avatarUrl,
                                      width: 100.0,
                                      borderRadius: BorderRadius.circular(0.0),
                                      replacement: Avatar(
                                        name: displayname,
                                        size: 100.0,
                                        borderRadius: BorderRadius.circular(
                                          0.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    displayname,
                                    style: const TextStyle(
                                      fontSize: titleFontSize,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (summary.adminUserIDs.isNotEmpty)
                                    _CourseAdminDisplay(summary),
                                  Text(
                                    course.description,
                                    style: const TextStyle(
                                      fontSize: descFontSize,
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 8.0,
                                    runSpacing: 8.0,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      CourseInfoChip(
                                        icon: Icons.language,
                                        text: course.targetLanguage
                                            .toUpperCase(),
                                        fontSize: descFontSize,
                                        iconSize: smallIconSize,
                                      ),
                                      if (courseCefr != null)
                                        CourseInfoChip(
                                          icon: Icons.school,
                                          text: courseCefr.title(context),
                                          fontSize: descFontSize,
                                          iconSize: smallIconSize,
                                          highlightColor: cefrMatch.chipColor,
                                        ),
                                      CourseInfoChip(
                                        icon: Icons.location_on,
                                        text: L10n.of(
                                          context,
                                        ).numModules(course.sequence.length),
                                        fontSize: descFontSize,
                                        iconSize: smallIconSize,
                                      ),
                                      CourseInfoChip(
                                        icon: Icons.person,
                                        text: L10n.of(context)
                                            .countParticipants(
                                              summary.joinedMemberCount,
                                            ),
                                        fontSize: descFontSize,
                                        iconSize: smallIconSize,
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 4.0,
                                      bottom: 8.0,
                                    ),
                                    child: Row(
                                      spacing: 4.0,
                                      children: [
                                        const Icon(
                                          Icons.map,
                                          size: largeIconSize,
                                        ),
                                        Text(
                                          L10n.of(context).coursePlan,
                                          style: const TextStyle(
                                            fontSize: titleFontSize,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }

                            // world_v2: render the plan from the v3 quest
                            // outline (read-only preview, no room). shrinkWrap:
                            // embedded in the page's outer scroll view.
                            return CourseObjectivesList(
                              questId: course.id,
                              shrinkWrap: true,
                              objectivesProvider: controller.objectivesProvider,
                            );
                          },
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border(
                          top: BorderSide(
                            color: theme.dividerColor,
                            width: 1.0,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.all(12.0),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Column(
                          spacing: 8.0,
                          children: [
                            if (cefrMatch.message != null)
                              InlineTooltip(
                                message: cefrMatch.message!,
                                isClosed: false,
                                backgroundColor: cefrMatch.chipColor,
                                icon: cefrMatch.icon,
                              ),
                            if (summary.joinRule == JoinRules.knock) ...[
                              TextField(
                                decoration: InputDecoration(
                                  hintText: L10n.of(context).enterCodeToJoin,
                                ),
                                onSubmitted: controller.joinWithCode,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(10),
                                ],
                              ),
                              Row(
                                spacing: 8.0,
                                children: [
                                  const Expanded(child: Divider()),
                                  Text(L10n.of(context).or),
                                  const Expanded(child: Divider()),
                                ],
                              ),
                            ],
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onPrimaryContainer,
                              ),
                              onPressed: controller.joinCourse,
                              child: Row(
                                spacing: 8.0,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.map_outlined),
                                  Text(
                                    summary.joinRule == JoinRules.knock
                                        ? L10n.of(context).knock
                                        : L10n.of(context).join,
                                    style: const TextStyle(
                                      fontSize: titleFontSize,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CourseAdminDisplay extends StatelessWidget {
  final RoomSummaryResponse summary;
  const _CourseAdminDisplay(this.summary);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12.0,
      runSpacing: 12.0,
      children: [
        ...summary.adminUserIDs.map((adminId) {
          return FutureBuilder(
            future: Matrix.of(context).client.getProfileFromUserId(adminId),
            builder: (context, snapshot) {
              final profile = snapshot.data;
              final displayName =
                  profile?.displayName ?? adminId.localpart ?? adminId;
              return InkWell(
                onTap: profile != null
                    ? () => UserDialog.show(
                        context: context,
                        profile: profile,
                        uri: GoRouterState.of(context).uri,
                      )
                    : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18.0),
                  ),
                  padding: const EdgeInsets.all(4.0),
                  child: Opacity(
                    opacity: 0.5,
                    child: Row(
                      spacing: 4.0,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Avatar(
                          size: 18.0,
                          mxContent: profile?.avatarUrl,
                          name: displayName,
                          userId: adminId,
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 80.0),
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 12.0,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}

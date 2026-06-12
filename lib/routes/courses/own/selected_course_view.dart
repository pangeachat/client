import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/course_plans/map_clipper.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/routes/courses/cefr_level_match.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/routes/courses/course_topic_list_widget.dart';
import 'package:fluffychat/routes/courses/own/selected_course_page.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

class SelectedCourseView extends StatelessWidget {
  final SelectedCourseController controller;
  const SelectedCourseView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const double titleFontSize = 16.0;
    const double descFontSize = 12.0;

    const double largeIconSize = 24.0;
    const double mediumIconSize = 16.0;
    const double smallIconSize = 12.0;

    final course = controller.course;

    final userController = MatrixState.pangeaController.userController;
    final cefrMatch = course == null
        ? CefrMatchResult.none
        : computeCefrMatch(
            context: context,
            userLevel: userController.userCefrLevel,
            courseLevel: course.cefrLevel,
            courseLanguage: course.targetLanguage,
            userLanguage: userController.userL2Code,
          );

    return Scaffold(
      appBar: AppBar(title: Text(controller.title)),
      body: SafeArea(
        child: Container(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500.0),
            child: controller.loadingCourse
                ? const Center(child: CircularProgressIndicator.adaptive())
                : controller.courseError != null || course == null
                ? Center(
                    child: ErrorIndicator(
                      message: L10n.of(context).oopsSomethingWentWrong,
                    ),
                  )
                : Column(
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
                              final String displayname = course.title;

                              if (index == 0) {
                                return Column(
                                  spacing: 8.0,
                                  children: [
                                    ClipPath(
                                      clipper: MapClipper(),
                                      child: ImageByUrl(
                                        imageUrl: course.imageUrl,
                                        width: 100.0,
                                        borderRadius: BorderRadius.circular(
                                          0.0,
                                        ),
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
                                    ),
                                    Text(
                                      course.description,
                                      style: const TextStyle(
                                        fontSize: descFontSize,
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 8.0,
                                      runSpacing: 8.0,
                                      children: [
                                        CourseInfoChip(
                                          icon: Icons.language,
                                          text: course.targetLanguageDisplay,
                                          fontSize: descFontSize,
                                          iconSize: smallIconSize,
                                        ),
                                        CourseInfoChip(
                                          icon: Icons.school,
                                          text: course.cefrLevel.title(context),
                                          fontSize: descFontSize,
                                          iconSize: smallIconSize,
                                          highlightColor: cefrMatch.chipColor,
                                        ),
                                        CourseInfoChip(
                                          icon: Icons.location_on,
                                          text: L10n.of(
                                            context,
                                          ).numModules(course.topicIds.length),
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

                              return CourseTopicList(course: course);
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
                        child: Column(
                          spacing: 8.0,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (cefrMatch.message != null)
                              InlineTooltip(
                                message: cefrMatch.message!,
                                isClosed: false,
                                backgroundColor: cefrMatch.chipColor,
                                icon: cefrMatch.icon,
                              ),
                            Row(
                              spacing: 12.0,
                              children: [
                                const Icon(Icons.edit, size: mediumIconSize),
                                Flexible(
                                  child: Text(
                                    L10n.of(context).editCourseLater,
                                    style: const TextStyle(
                                      fontSize: descFontSize,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              spacing: 12.0,
                              children: [
                                const Icon(Icons.shield, size: mediumIconSize),
                                Flexible(
                                  child: Text(
                                    L10n.of(context).newCourseAccess,
                                    style: const TextStyle(
                                      fontSize: descFontSize,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Column(
                                spacing: 8.0,
                                children: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          theme.colorScheme.primaryContainer,
                                      foregroundColor:
                                          theme.colorScheme.onPrimaryContainer,
                                    ),
                                    onPressed: () => showFutureLoadingDialog(
                                      context: context,
                                      future: () => controller.submit(course),
                                    ),
                                    child: Row(
                                      spacing: 8.0,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.map_outlined),
                                        Text(
                                          controller.buttonText,
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
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

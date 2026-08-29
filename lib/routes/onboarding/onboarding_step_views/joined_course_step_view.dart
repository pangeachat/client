import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_forward_button.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';

class JoinedCourseStepView extends StatelessWidget {
  final JoinedCourseOnboardingStep step;
  final bool loading;
  final bool hasNextStep;
  final VoidCallback forward;

  const JoinedCourseStepView({
    super.key,
    required this.step,
    required this.loading,
    required this.hasNextStep,
    required this.forward,
  });

  Room? get _room {
    final roomId = step.state.joinedRoomId;
    if (roomId == null) return null;
    return step.client.getRoomById(roomId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coursePlan = step.state.joinedCoursePlan;
    final room = _room;
    final admin = room?.nonBotRoomAdminsLocal.firstOrNull;

    return Column(
      spacing: 32.0,
      children: [
        Expanded(
          child: Center(
            child: Column(
              spacing: 12.0,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  L10n.of(context).joinedCourseStepTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (admin != null)
                  Padding(
                    padding: EdgeInsetsGeometry.symmetric(horizontal: 16.0),
                    child: Container(
                      padding: EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.primaryContainer,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      child: Row(
                        spacing: 12.0,
                        children: [
                          Avatar(
                            mxContent: admin.avatarUrl,
                            name: admin.calcDisplayname(),
                            size: 40,
                            userId: admin.id,
                          ),
                          Text(admin.calcDisplayname()),
                        ],
                      ),
                    ),
                  ),
                if (room != null || coursePlan != null)
                  Padding(
                    padding: EdgeInsetsGeometry.symmetric(horizontal: 16.0),
                    child: Container(
                      padding: EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.primaryContainer,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      child: Column(
                        spacing: 10.0,
                        children: [
                          SizedBox(
                            height: 120.0,
                            child: Row(
                              spacing: 10.0,
                              children: [
                                Avatar(
                                  mxContent: room?.avatar,
                                  name: room?.getLocalizedDisplayname(
                                    MatrixLocals(L10n.of(context)),
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  size: 120.0,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        coursePlan?.title ??
                                            room?.getLocalizedDisplayname(
                                              MatrixLocals(L10n.of(context)),
                                            ) ??
                                            '',
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      if (coursePlan != null)
                                        Wrap(
                                          spacing: 4.0,
                                          runSpacing: 2.0,
                                          children: [
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 4.0,
                                              ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                color: theme
                                                    .colorScheme
                                                    .surfaceContainer,
                                              ),
                                              child: CourseInfoChip(
                                                icon: Icons.language_outlined,
                                                text: coursePlan
                                                    .targetLanguageDisplay,
                                                fontSize: 14,
                                                iconSize: 12,
                                              ),
                                            ),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 4.0,
                                              ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                color: theme
                                                    .colorScheme
                                                    .surfaceContainer,
                                              ),
                                              child: CourseInfoChip(
                                                icon: Icons.school_outlined,
                                                text:
                                                    coursePlan.cefrLevel.string,
                                                fontSize: 14,
                                                iconSize: 12,
                                              ),
                                            ),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 4.0,
                                              ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                color: theme
                                                    .colorScheme
                                                    .surfaceContainer,
                                              ),
                                              child: CourseInfoChip(
                                                icon: Icons.event_note_outlined,
                                                text: L10n.of(context)
                                                    .numModules(
                                                      coursePlan
                                                          .topicIds
                                                          .length,
                                                    ),
                                                fontSize: 14,
                                                iconSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (coursePlan != null)
                            Text(
                              coursePlan.description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        OnboardingForwardButton(
          onPressed: step.enableGoForward ? forward : null,
          loading: loading,
          label: hasNextStep
              ? step.nextStepText(L10n.of(context))
              : step.lastStepText(L10n.of(context)),
        ),
      ],
    );
  }
}

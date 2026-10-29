import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_forward_button.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_step_body.dart';
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
    final hasTeacher = room?.nonBotRoomAdminsLocal.isNotEmpty ?? false;

    return Column(
      spacing: 32.0,
      children: [
        Expanded(
          child: Center(
            child: OnboardingStepBody(
              label: L10n.of(context).joinedCourseStepTitle,
              child: Column(
                spacing: 12.0,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      L10n.of(context).joinedCourseStepTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (hasTeacher)
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
                        // "Your teacher", naming no one: a course can have
                        // several teachers and the first admin here need not
                        // be the one who invited the student (owner, 2026-10-28).
                        child: Row(
                          spacing: 12.0,
                          children: [
                            const Icon(Icons.school_outlined, size: 40),
                            Text(L10n.of(context).yourTeacher),
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
                                          CourseInfoChips(
                                            coursePlan.uuid,
                                            courseRoomId: room?.id,
                                            fontSize: 14,
                                            iconSize: 12,
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
                  // Joining a central course puts the learner in front of
                  // strangers, so the page says so (joining-courses
                  // .instructions.md § The central course).
                  if (step.state.joinedCentralCourse)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        L10n.of(context).centralCourseMembersSeeYou,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
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
